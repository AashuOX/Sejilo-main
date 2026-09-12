import {
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { randomBytes, randomInt, createHash, timingSafeEqual } from 'crypto';
import { OAuth2Client } from 'google-auth-library';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { GoogleLoginDto } from './dto/google-login.dto';
import { VerifyPhoneOtpDto } from './dto/verify-phone-otp.dto';
import { EmailService } from './email.service';
import { SmsService } from './sms.service';
import { WebhooksService } from '../webhooks/webhooks.service';

@Injectable()
export class AuthService {
  private readonly googleClient: OAuth2Client;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly config: ConfigService,
    private readonly emailService: EmailService,
    private readonly smsService: SmsService,
    private readonly redis: RedisService,
    private readonly webhooks: WebhooksService,
  ) {
    // The audience is always passed explicitly to verifyIdToken, so this only
    // sets the client's default; the first configured id keeps it sensible when
    // GOOGLE_CLIENT_ID holds a comma-separated list.
    this.googleClient = new OAuth2Client(
      this.config.get<string>('GOOGLE_CLIENT_ID', '').split(',')[0].trim(),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  private hashToken(token: string): string {
      return createHash('sha256').update(token).digest('hex');
    }

    private calculateAge(birthDate: Date): number {
      const today = new Date();
      let age = today.getFullYear() - birthDate.getFullYear();
      const monthDiff = today.getMonth() - birthDate.getMonth();
      if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
        age--;
      }
      return age;
    }

    private validateAge(birthDate: Date): void {
      const age = this.calculateAge(birthDate);
      const MINIMUM_AGE = 13;
      if (age < MINIMUM_AGE) {
        throw new BadRequestException(`You must be at least ${MINIMUM_AGE} years old to register.`);
      }
    }

  private generateTokenPair(userId: string, email: string | null, sessionId: string) {
    const payload = { sub: userId, userId, email, sessionId };
    const accessToken = this.jwtService.sign(payload, {
      expiresIn: this.config.get<string>('JWT_EXPIRES_IN', '7d') as any,
    });
    const refreshToken = randomBytes(40).toString('hex');
    return { accessToken, refreshToken };
  }

  /** Persist a new session row and return it (so its real id can be embedded in the JWT). */
  private createSession(userId: string) {
    return this.prisma.session.create({
      data: {
        userId,
        tokenHash: this.hashToken(randomBytes(32).toString('hex')),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      } as any,
    });
  }

  /** Sign a token pair bound to a real session id, then store the token hashes on that session. */
  private async issueTokens(user: { id: string; email: string | null }, sessionId: string) {
    const { accessToken, refreshToken } = this.generateTokenPair(user.id, user.email, sessionId);
    await this.prisma.session.update({
      where: { id: sessionId },
      data: {
        tokenHash: this.hashToken(accessToken),
        refreshToken: this.hashToken(refreshToken),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });
    return { accessToken, refreshToken };
  }

  /**
   * Client ids this server accepts Google credentials for.
   *
   * `GOOGLE_CLIENT_ID` may hold a comma-separated list so that a second
   * platform client (a native Android or desktop OAuth client) can be added
   * without a code change. Every entry is treated as an allowed audience;
   * nothing else is.
   */
  private googleAudiences(): string[] {
    return this.config
      .get<string>('GOOGLE_CLIENT_ID', '')
      .split(',')
      .map((id) => id.trim())
      .filter((id) => id.length > 0);
  }

  /**
   * Verify a Google credential and return only claims Google vouched for.
   *
   * Both accepted shapes are bound to this application's client id, which is
   * what stops a credential minted for some other Google OAuth client from
   * logging its holder in here:
   *
   *   * `idToken` — `verifyIdToken` checks the signature, issuer, expiry and
   *     the `aud` claim against `GOOGLE_CLIENT_ID`.
   *   * `accessToken` — an opaque string that carries no verifiable claims, so
   *     it is introspected at `oauth2.googleapis.com/tokeninfo`, which returns
   *     the `aud` it was issued for. That audience is then checked the same
   *     way. Do NOT read identity from `/userinfo` instead: that endpoint
   *     answers for any valid token regardless of who it was issued to.
   *
   * `dto.email` / `dto.googleId` are never consulted here. They arrive from
   * the client and an attacker controls them, so treating them as claims would
   * let anyone sign in as any account.
   *
   * An email is returned only when Google reports it as verified: the caller
   * links accounts by email, and an unverified address would let a Google
   * account created with someone else's address take over their user.
   */
  private async verifyGoogleToken(dto: GoogleLoginDto): Promise<{
    sub?: string;
    email?: string;
    name?: string;
    picture?: string;
  }> {
    const audiences = this.googleAudiences();

    if (audiences.length === 0) {
      // Without an audience to pin the credential to there is no way to tell a
      // token meant for this app from one meant for any other, so fail closed
      // rather than trust whatever the client sent.
      console.error('Google sign-in rejected: GOOGLE_CLIENT_ID is not set.');
      throw new ServiceUnavailableException(
        'Google sign-in is not configured on this server.',
      );
    }

    if (!dto.idToken && !dto.accessToken) {
      return {};
    }

    if (dto.idToken) {
      try {
        const ticket = await this.googleClient.verifyIdToken({
          idToken: dto.idToken,
          audience: audiences,
        });
        const p = ticket.getPayload();
        if (p?.sub) {
          return {
            sub: p.sub,
            email: p.email_verified === true ? p.email : undefined,
            name: p.name,
            picture: p.picture,
          };
        }
      } catch (error) {
        console.error(
          'Google idToken verification failed:',
          error instanceof Error ? error.message : String(error),
        );
      }
    }

    if (dto.accessToken) {
      try {
        const response = await fetch(
          'https://oauth2.googleapis.com/tokeninfo?access_token=' +
            encodeURIComponent(dto.accessToken),
          { signal: AbortSignal.timeout(5000) },
        );
        if (response.ok) {
          const info = (await response.json()) as {
            aud?: string;
            sub?: string;
            email?: string;
            // tokeninfo reports booleans as strings for this endpoint.
            email_verified?: string | boolean;
          };
          if (info.sub && info.aud && audiences.includes(info.aud)) {
            const emailVerified =
              info.email_verified === true || info.email_verified === 'true';
            return {
              sub: info.sub,
              email: emailVerified ? info.email : undefined,
            };
          }
          console.error(
            'Google accessToken rejected: issued for another client id.',
          );
        }
      } catch (error) {
        console.error(
          'Google accessToken verification failed:',
          error instanceof Error ? error.message : String(error),
        );
      }
    }

    return {};
  }

  // ── Auth flows ─────────────────────────────────────────────────────────

  async register(dto: RegisterDto) {
    const normalizedEmail = dto.email.trim().toLowerCase();
    const normalizedUsername = dto.username.trim().toLowerCase();

    if (dto.dateOfBirth) this.validateAge(dto.dateOfBirth);

    const existing = await this.prisma.user.findFirst({
      where: {
        OR: [
          { email: normalizedEmail },
          { profile: { username: normalizedUsername } },
        ],
      },
    });

    if (existing) {
      throw new ConflictException('Email or username is already in use.');
    }

    const salt = await bcrypt.genSalt(12);
    const passwordHash = await bcrypt.hash(dto.password, salt);

    const user = await this.prisma.user.create({
      data: {
        email: normalizedEmail,
        passwordHash,
        birthDate: dto.dateOfBirth,
        profile: {
          create: {
            username: normalizedUsername,
            displayName: dto.displayName.trim(),
            bio: dto.bio?.trim() ?? '',
          },
        },
      },
      include: { profile: true },
    });

    const session = await this.createSession(user.id);
    const { accessToken, refreshToken } = await this.issueTokens(user, session.id);

    await this.webhooks.onUserRegistered({
      userId: user.id,
      email: user.email ?? undefined,
      username: user.profile?.username,
      provider: 'email',
      createdAt: user.createdAt.toISOString(),
    });

    return {
      id: user.id,
      token: accessToken,
      refreshToken,
      isNewUser: true,
      profile: {
        id: user.id,
        email: user.email,
        username: user.profile?.username,
        displayName: user.profile?.displayName,
        bio: user.profile?.bio ?? '',
        avatar: null,
        createdAt: user.createdAt.toISOString(),
      },
    };
  }

  async login(dto: LoginDto) {
    const identifier = dto.email.trim().toLowerCase();
    const user = await this.prisma.user.findFirst({
      where: {
        OR: [
          { email: identifier },
          { profile: { username: identifier } },
        ],
      },
      include: { profile: true },
    });

    if (!user || !user.passwordHash || !user.isActive) {
      throw new UnauthorizedException('Invalid email, username or password.');
    }

    const isValid = await bcrypt.compare(dto.password, user.passwordHash);
    if (!isValid) {
      throw new UnauthorizedException('Invalid email or password.');
    }

    const session = await this.createSession(user.id);
    const { accessToken, refreshToken } = await this.issueTokens(user, session.id);

    await this.webhooks.onUserLoggedIn({
      userId: user.id,
      provider: 'email',
      createdAt: new Date().toISOString(),
    });

    return {
      id: user.id,
      token: accessToken,
      refreshToken,
      isNewUser: false,
      profile: {
        id: user.id,
        email: user.email,
        username: user.profile?.username ?? '',
        displayName: user.profile?.displayName ?? '',
        bio: user.profile?.bio ?? '',
        avatar:
          user.profile?.avatarBytes && user.profile?.avatarMimeType
            ? {
                mimeType: user.profile.avatarMimeType,
                data: Buffer.from(user.profile.avatarBytes).toString('base64url'),
              }
            : null,
        createdAt: user.createdAt.toISOString(),
      },
    };
  }

async loginWithGoogle(dto: GoogleLoginDto) {
    if (dto.dateOfBirth) this.validateAge(dto.dateOfBirth);

    // 1. Verify token and extract claims
    const claims = await this.verifyGoogleToken(dto);

    // Identity comes only from verifyGoogleToken, which returns nothing unless
    // Google signed for it. dto.email / dto.googleId are attacker-controlled
    // and are never promoted to claims, so an unverified request stops here.
    if (!claims.sub && !claims.email) {
      throw new UnauthorizedException(
        'Google token verification failed. Provide a valid idToken or accessToken.',
      );
    }

    // Lookup/account-linking and account creation use only verified claims.
    // DTO profile fields are presentation hints only; an attacker must never
    // be able to claim an arbitrary email address during account creation.
    const claimsEmail = claims.email?.trim().toLowerCase();
    const googleId = claims.sub?.trim();
    const displayName = (claims.name ?? dto.displayName)?.trim();
    const photoUrl = (claims.picture ?? dto.photoUrl)?.trim();

    let isNewUser = false;

    // Two ordered queries rather than one OR: the Google subject is the stable
    // identifier and must win when a *different* user happens to hold the
    // address. A single findFirst with both branches has no defined order, so
    // which row came back would be up to the query planner.
    let user = googleId
      ? await this.prisma.user.findFirst({
          where: { authIdentities: { some: { provider: 'google', providerId: googleId } } },
          include: { profile: true },
        })
      : null;

    if (!user && claimsEmail) {
      user = await this.prisma.user.findUnique({
        where: { email: claimsEmail },
        include: { profile: true },
      });
    }

    // A disabled account must not come back through the Google door — this is
    // the same gate password login applies.
    if (user && !user.isActive) {
      throw new UnauthorizedException('This account has been disabled.');
    }

    if (!user) {
      isNewUser = true;
      const email = claimsEmail ?? null;
      const base = (email ? email.split('@')[0] : 'user')
        .toLowerCase()
        .replace(/[^a-z0-9_]/g, '')
        .slice(0, 20) || 'user';
      // profiles.username is unique, and email local-parts repeat often enough
      // ("john", "info") that a single random suffix would eventually collide
      // and fail the signup with a 500. uniqueUsername retries against the
      // table, exactly as the phone-OTP signup does.
      const username = await this.uniqueUsername(`${base}_${randomInt(1000, 9999)}`);

      user = await this.prisma.user.create({
        data: {
          email: email ?? null,
          // validateAge() above already gated on this; keep it so the gate is
          // reproducible later instead of being enforced and then discarded.
          birthDate: dto.dateOfBirth,
          profile: {
            create: {
              username,
              displayName: displayName || base,
              bio: '',
              avatarUrl: photoUrl ?? null,
            },
          },
          authIdentities: googleId
            ? {
                create: {
                  provider: 'google',
                  providerId: googleId,
                  email: email ?? null,
                },
              }
            : undefined,
        },
        include: { profile: true },
      });
} else if (googleId) {
      // Upsert auth identity for existing user who logged in for the first time via Google
      await this.prisma.authIdentity.upsert({
        where: { provider_providerId: { provider: 'google', providerId: googleId } },
        create: {
          userId: user.id,
          provider: 'google',
          providerId: googleId,
          email: claimsEmail ?? null,
        },
        update: { email: claimsEmail ?? null },
      }).catch(() => {});
    }

    const session = await this.createSession(user.id);
    const { accessToken, refreshToken } = await this.issueTokens(user, session.id);

    if (isNewUser) {
      await this.webhooks.onUserRegistered({
        userId: user.id,
        email: user.email ?? undefined,
        username: user.profile?.username,
        provider: 'google',
        createdAt: user.createdAt.toISOString(),
      });
    }
    await this.webhooks.onUserLoggedIn({
      userId: user.id,
      provider: 'google',
      createdAt: new Date().toISOString(),
    });

    return {
      id: user.id,
      token: accessToken,
      refreshToken,
      isNewUser,
      profile: {
        id: user.id,
        email: user.email,
        username: user.profile?.username ?? '',
        displayName: user.profile?.displayName ?? '',
        bio: user.profile?.bio ?? '',
        avatar:
          user.profile?.avatarBytes && user.profile?.avatarMimeType
            ? {
                mimeType: user.profile.avatarMimeType,
                data: Buffer.from(user.profile.avatarBytes).toString('base64url'),
              }
            : null,
        createdAt: user.createdAt.toISOString(),
      },
    };
  }

  // ── Phone OTP authentication ────────────────────────────────

  private normalizePhone(phoneNumber: string): string {
    return phoneNumber.replace(/[^0-9+]/g, '');
  }

  private async buildProfilePayload(user: {
    id: string;
    email: string | null;
    profile: any;
  }) {
    return {
      id: user.id,
      email: user.email,
      username: user.profile?.username ?? '',
      displayName: user.profile?.displayName ?? '',
      bio: user.profile?.bio ?? '',
      avatar:
        user.profile?.avatarBytes && user.profile?.avatarMimeType
          ? {
              mimeType: user.profile.avatarMimeType,
              data: Buffer.from(user.profile.avatarBytes).toString('base64url'),
            }
          : null,
    };
  }

  /** Step 1: request an OTP for a phone number. Rate-limited and stored in Redis. */
  async requestPhoneOtp(phoneNumber: string) {
    const normalized = this.normalizePhone(phoneNumber);
    if (!/^\+[1-9]\d{7,14}$/.test(normalized)) {
      throw new BadRequestException('Phone number must be in E.164 format (e.g. +1234567890).');
    }

    // Rate limit: one OTP request per phone number per 60 seconds
    const rateKey = `otp:rl:${normalized}`;
    if (await this.redis.getClient()?.get(rateKey)) {
      throw new HttpException('Too many requests. Try again in a minute.', HttpStatus.TOO_MANY_REQUESTS);
    }

    const code = randomInt(100000, 999999).toString();
    const otpKey = `otp:phone:${normalized}`;
    await this.redis.getClient()?.set(otpKey, code, 'EX', 300);
    await this.redis.getClient()?.set(rateKey, '1', 'EX', 60);

    await this.smsService.sendOtp(normalized, code);

    // The code is only ever echoed back outside production. With no SMS
    // provider configured, returning it in the response would otherwise let
    // anyone who knows a phone number mint a valid OTP for it and sign in as
    // that account — so on a deployment without Twilio the code stays in the
    // server log only, and phone sign-in is unavailable to real users until a
    // provider is configured.
    const exposeCode =
      !this.smsService.isConfigured &&
      this.config.get<string>('NODE_ENV', 'development') !== 'production';

    return {
      accepted: true,
      expiresInSeconds: 300,
      devCode: exposeCode ? code : undefined,
    };
  }

  /** Step 2: verify the OTP and sign in (or register) the phone user. */
  async verifyPhoneOtp(dto: VerifyPhoneOtpDto) {
    const normalized = this.normalizePhone(dto.phoneNumber);
    const otpKey = `otp:phone:${normalized}`;
    const stored = await this.redis.getClient()?.get(otpKey);

    if (!stored) {
      throw new BadRequestException('Code is invalid or has expired. Request a new code.');
    }

    const a = Buffer.from(stored);
    const b = Buffer.from(dto.code);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new BadRequestException('Code is invalid or has expired. Request a new code.');
    }

    await this.redis.getClient()?.del(otpKey);

    let isNewUser = false;
    let user = await this.prisma.user.findUnique({
      where: { phone: normalized },
      include: { profile: true },
    });

    if (!user) {
          isNewUser = true;
          if (dto.dateOfBirth) this.validateAge(dto.dateOfBirth);
          const suffix = normalized.replace('+', '');
          const base = dto.username?.trim().toLowerCase() || `phone_${suffix.slice(-4)}`;
          const uniqueBase = base.replace(/[^a-z0-9_]/g, '').slice(0, 20) || 'user';
          const safeUsername = await this.uniqueUsername(uniqueBase);

          user = await this.prisma.user.create({
            data: {
              phone: normalized,
              birthDate: dto.dateOfBirth,
              profile: {
                create: {
                  username: safeUsername,
                  displayName: dto.displayName?.trim() || `User ${suffix.slice(-4)}`,
                  bio: '',
                },
              },
            },
            include: { profile: true },
          });
        }

    const session = await this.createSession(user.id);
    const { accessToken, refreshToken } = await this.issueTokens(user, session.id);

    if (isNewUser) {
      await this.webhooks.onUserRegistered({
        userId: user.id,
        username: user.profile?.username,
        provider: 'phone',
        createdAt: user.createdAt.toISOString(),
      });
    }
    await this.webhooks.onUserLoggedIn({
      userId: user.id,
      provider: 'phone',
      createdAt: new Date().toISOString(),
    });

    return {
      id: user.id,
      token: accessToken,
      refreshToken,
      isNewUser,
      profile: await this.buildProfilePayload(user as any),
    };
  }

  private async uniqueUsername(base: string): Promise<string> {
    let candidate = base;
    for (let i = 0; i < 20; i++) {
      const exists = await this.prisma.profile.findUnique({
        where: { username: candidate },
      });
      if (!exists) return candidate;
      candidate = `${base.slice(0, 16)}_${randomInt(1000, 9999)}`;
    }
    return `${base.slice(0, 12)}_${Date.now().toString(36)}`;
  }

  async refreshToken(rawRefreshToken: string) {
    const hashed = this.hashToken(rawRefreshToken);
    const session = await this.prisma.session.findUnique({
      where: { refreshToken: hashed },
      include: { user: { include: { profile: true } } },
    });

    if (!session || (session.expiresAt && session.expiresAt < new Date()) || session.revokedAt) {
      throw new UnauthorizedException('Invalid or expired refresh token.');
    }

    const user = session.user;
    const { accessToken, refreshToken: newRefresh } = this.generateTokenPair(
      user.id,
      user.email,
      session.id,
    );

    await this.prisma.session.update({
      where: { id: session.id },
      data: {
        tokenHash: this.hashToken(accessToken),
        refreshToken: this.hashToken(newRefresh),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    return { token: accessToken, refreshToken: newRefresh };
  }

  async requestPasswordReset(email: string) {
    const normalized = email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({ where: { email: normalized } });

    // Always return success to prevent user enumeration
    if (!user) return { accepted: true };

    // Generate a time-limited reset token (1 hour)
    const rawToken = randomBytes(32).toString('hex');
    const tokenHash = this.hashToken(rawToken);

    // Store token in a dedicated session with short expiry
    await this.prisma.session.create({
      data: {
        userId: user.id,
        tokenHash,
        expiresAt: new Date(Date.now() + 60 * 60 * 1000), // 1 hour
      },
    });

    await this.emailService.sendPasswordResetEmail(normalized, rawToken);
    return { accepted: true };
  }

  async resetPassword(token: string, newPass: string) {
    if (newPass.length < 8) {
      throw new BadRequestException('Password must be at least 8 characters long.');
    }

    const hashed = this.hashToken(token);
    const session = await this.prisma.session.findUnique({
      where: { tokenHash: hashed },
    });

    if (!session || session.expiresAt < new Date() || session.revokedAt) {
      throw new BadRequestException('Reset token is invalid or has expired.');
    }

    const salt = await bcrypt.genSalt(12);
    const passwordHash = await bcrypt.hash(newPass, salt);

    await this.prisma.user.update({
      where: { id: session.userId },
      data: { passwordHash },
    });

    // Revoke all sessions for this user
    await this.prisma.session.updateMany({
      where: { userId: session.userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });

    return { success: true };
  }

  async logout(userId: string, sessionId?: string) {
    if (sessionId) {
      await this.prisma.session.updateMany({
        where: { userId, id: sessionId },
        data: { revokedAt: new Date() },
      });
    } else {
      await this.prisma.session.updateMany({
        where: { userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    }
    await this.webhooks.onUserLoggedOut({
      userId,
      deviceId: sessionId,
      createdAt: new Date().toISOString(),
    });
    return { success: true };
  }

  async deleteAccount(userId: string) {
    await this.prisma.user.delete({ where: { id: userId } });
    return { success: true };
  }
}
