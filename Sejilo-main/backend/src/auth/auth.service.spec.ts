import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { OAuth2Client } from 'google-auth-library';
import { AuthService } from './auth.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { EmailService } from './email.service';
import { SmsService } from './sms.service';
import { WebhooksService } from '../webhooks/webhooks.service';

const CLIENT_ID = 'sejilo-test-client.apps.googleusercontent.com';
const OTHER_CLIENT_ID = 'someone-elses-app.apps.googleusercontent.com';

describe('AuthService (Google flows)', () => {
  let service: AuthService;
  let prisma: any;
  let verifyIdTokenMock: jest.Mock;
  let fetchMock: jest.Mock;
  // Mutable so a test can simulate a server with no GOOGLE_CLIENT_ID set.
  let configuredClientId: string;

  const profileOf = (id: string, email: string | null) => ({
    id,
    username: 'someuser',
    displayName: 'Some User',
    bio: '',
    avatarUrl: null,
  });

  /** A payload shaped like the real thing: Google always sends email_verified. */
  const idTokenPayload = (over: Record<string, unknown> = {}) => ({
    sub: 'google-sub-123',
    email: 'new.google@example.com',
    email_verified: true,
    name: 'New Google',
    picture: 'https://pic/1',
    ...over,
  });

  const tokenInfoResponse = (body: Record<string, unknown>) => ({
    ok: true,
    json: async () => body,
  });

  beforeAll(() => {
    verifyIdTokenMock = jest.fn();
    (OAuth2Client.prototype as any).verifyIdToken = verifyIdTokenMock;
    fetchMock = jest.fn();
    global.fetch = fetchMock as any;
  });

  beforeEach(async () => {
    configuredClientId = CLIENT_ID;
    prisma = {
      user: {
        findFirst: jest.fn().mockResolvedValue(null),
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn(),
        update: jest.fn(),
      },
      // uniqueUsername() checks this before creating a profile.
      profile: { findUnique: jest.fn().mockResolvedValue(null) },
      authIdentity: { upsert: jest.fn().mockResolvedValue({}) },
      session: {
        create: jest.fn().mockResolvedValue({ id: 'sess-1' }),
        update: jest.fn().mockResolvedValue({}),
      },
    };
    const jwtService = { sign: jest.fn().mockReturnValue('access.token.here') };
    const config = {
      get: jest.fn((key: string, def: any) => {
        if (key === 'JWT_EXPIRES_IN') return '7d';
        if (key === 'JWT_SECRET') return 'test-secret';
        if (key === 'GOOGLE_CLIENT_ID') return configuredClientId;
        return def ?? '';
      }),
    };
    const emailService = {
      sendWelcomeEmail: jest.fn().mockResolvedValue(undefined),
      sendPasswordResetEmail: jest.fn().mockResolvedValue(undefined),
      sendOtpEmail: jest.fn().mockResolvedValue(undefined),
    };
    const smsService = { sendOtp: jest.fn().mockResolvedValue({ ok: true }) };
    const redis = {
      get: jest.fn().mockResolvedValue(null),
      set: jest.fn().mockResolvedValue(undefined),
      del: jest.fn(),
    };
    const webhooksService = {
      onUserRegistered: jest.fn().mockResolvedValue(undefined),
      onUserLoggedIn: jest.fn().mockResolvedValue(undefined),
      onUserLoggedOut: jest.fn().mockResolvedValue(undefined),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: PrismaService, useValue: prisma },
        { provide: JwtService, useValue: jwtService },
        { provide: ConfigService, useValue: config },
        { provide: EmailService, useValue: emailService },
        { provide: SmsService, useValue: smsService },
        { provide: RedisService, useValue: redis },
        { provide: WebhooksService, useValue: webhooksService },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
    verifyIdTokenMock.mockReset();
    fetchMock.mockReset();
    // Nothing reaches Google in a unit test unless a case opts in.
    fetchMock.mockResolvedValue({ ok: false });
  });

  const createsUser = (id = 'user-new') =>
    prisma.user.create.mockImplementation(({ data }: any) =>
      Promise.resolve({
        id,
        email: data.email,
        isActive: true,
        createdAt: new Date(),
        profile: profileOf(id, data.email),
      }),
    );

  // ── Happy paths ────────────────────────────────────────────────────────

  it('creates a user from a verified ID token and ignores the spoofed dto fields', async () => {
    verifyIdTokenMock.mockResolvedValue({ getPayload: () => idTokenPayload() });
    createsUser();

    const result = await service.loginWithGoogle({
      idToken: 'real.jwt.token',
      email: 'spoofed@example.com',
      displayName: 'Spoofed',
      googleId: 'spoofed-sub',
      dateOfBirth: new Date('1990-01-01'),
    });

    expect(verifyIdTokenMock).toHaveBeenCalledWith({
      idToken: 'real.jwt.token',
      audience: [CLIENT_ID],
    });
    expect(result.isNewUser).toBe(true);
    expect(result.id).toBe('user-new');

    const created = prisma.user.create.mock.calls[0][0].data;
    expect(created.email).toBe('new.google@example.com');
    expect(created.birthDate).toEqual(new Date('1990-01-01'));
    expect(created.profile.create.displayName).toBe('New Google');
    expect(created.profile.create.avatarUrl).toBe('https://pic/1');
    expect(created.authIdentities.create.providerId).toBe('google-sub-123');
  });

  it('logs an existing Google identity in without a second lookup by email', async () => {
    verifyIdTokenMock.mockResolvedValue({
      getPayload: () => idTokenPayload({ sub: 'google-sub-456', email: 'existing@example.com' }),
    });
    prisma.user.findFirst.mockResolvedValue({
      id: 'user-existing',
      email: 'existing@example.com',
      isActive: true,
      createdAt: new Date(),
      profile: profileOf('user-existing', 'existing@example.com'),
    });

    const result = await service.loginWithGoogle({ idToken: 'real.jwt.token' });

    expect(prisma.user.findFirst).toHaveBeenCalledWith({
      where: { authIdentities: { some: { provider: 'google', providerId: 'google-sub-456' } } },
      include: { profile: true },
    });
    // The subject matched, so the address must not be used to pick a row: it
    // may belong to a different account.
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
    expect(result.isNewUser).toBe(false);
    expect(result.id).toBe('user-existing');
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('links a first-time Google login to the account holding the verified email', async () => {
    verifyIdTokenMock.mockResolvedValue({
      getPayload: () => idTokenPayload({ sub: 'google-sub-789', email: 'owner@example.com' }),
    });
    prisma.user.findFirst.mockResolvedValue(null);
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-owner',
      email: 'owner@example.com',
      isActive: true,
      createdAt: new Date(),
      profile: profileOf('user-owner', 'owner@example.com'),
    });

    const result = await service.loginWithGoogle({ idToken: 'real.jwt.token' });

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { email: 'owner@example.com' },
      include: { profile: true },
    });
    expect(prisma.authIdentity.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { provider_providerId: { provider: 'google', providerId: 'google-sub-789' } },
      }),
    );
    expect(result.id).toBe('user-owner');
    expect(result.isNewUser).toBe(false);
  });

  it('accepts an access token that was issued for this application', async () => {
    fetchMock.mockResolvedValue(
      tokenInfoResponse({
        aud: CLIENT_ID,
        sub: 'google-sub-at',
        email: 'at.user@example.com',
        email_verified: 'true',
      }),
    );
    createsUser('user-at');

    const result = await service.loginWithGoogle({ accessToken: 'ya29.valid-for-this-app' });

    // Identity must come from tokeninfo, which reports the audience. /userinfo
    // answers for a token issued to any client and cannot be used here.
    const calledUrl = String(fetchMock.mock.calls[0][0]);
    expect(calledUrl).toContain('oauth2.googleapis.com/tokeninfo');
    expect(calledUrl).not.toContain('userinfo');
    expect(result.id).toBe('user-at');
    expect(prisma.user.create.mock.calls[0][0].data.email).toBe('at.user@example.com');
  });

  // ── Rejections ─────────────────────────────────────────────────────────

  it('rejects an unverifiable ID token with 401 and touches no rows', async () => {
    verifyIdTokenMock.mockRejectedValue(new Error('Invalid token signature'));

    await expect(service.loginWithGoogle({ idToken: 'forged.jwt.token' })).rejects.toThrow(
      UnauthorizedException,
    );

    expect(prisma.user.findFirst).not.toHaveBeenCalled();
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('rejects a request carrying email/googleId but no token at all', async () => {
    await expect(
      service.loginWithGoogle({ email: 'victim@example.com', googleId: 'attacker-supplied-id' }),
    ).rejects.toThrow(UnauthorizedException);

    expect(verifyIdTokenMock).not.toHaveBeenCalled();
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
  });

  it('rejects an access token minted for a different Google client (token substitution)', async () => {
    fetchMock.mockResolvedValue(
      tokenInfoResponse({
        aud: OTHER_CLIENT_ID,
        sub: 'victim-sub',
        email: 'victim@example.com',
        email_verified: 'true',
      }),
    );

    await expect(
      service.loginWithGoogle({ accessToken: 'ya29.minted-for-another-app' }),
    ).rejects.toThrow(UnauthorizedException);

    expect(prisma.user.findFirst).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('fails closed with 503 when GOOGLE_CLIENT_ID is unset instead of trusting the dto', async () => {
    configuredClientId = '';

    await expect(
      service.loginWithGoogle({
        idToken: 'anything',
        email: 'victim@example.com',
        googleId: 'victim-google-sub',
      }),
    ).rejects.toThrow(ServiceUnavailableException);

    expect(verifyIdTokenMock).not.toHaveBeenCalled();
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  // ── Multiple allowed audiences ─────────────────────────────────────────
  //
  // GOOGLE_CLIENT_ID accepts a comma-separated list so a second platform client
  // (a native Android or desktop OAuth client that mints its own tokens) can be
  // added in the dashboard without a code change. render.yaml and
  // docs/GOOGLE_SIGNIN.md both document that, so it is tested rather than
  // assumed.

  it('passes every configured client id to verifyIdToken and accepts the second one', async () => {
    configuredClientId = `${OTHER_CLIENT_ID}, ${CLIENT_ID}`;
    verifyIdTokenMock.mockResolvedValue({ getPayload: () => idTokenPayload() });
    createsUser('user-second-audience');

    const result = await service.loginWithGoogle({ idToken: 'real.jwt.token' });

    expect(verifyIdTokenMock).toHaveBeenCalledWith({
      idToken: 'real.jwt.token',
      // Trimmed, in that order, and nothing else is allowed.
      audience: [OTHER_CLIENT_ID, CLIENT_ID],
    });
    expect(result.id).toBe('user-second-audience');
  });

  it('accepts an access token issued for the second configured client id', async () => {
    configuredClientId = `${CLIENT_ID},${OTHER_CLIENT_ID}`;
    fetchMock.mockResolvedValue(
      tokenInfoResponse({
        aud: OTHER_CLIENT_ID,
        sub: 'google-sub-second',
        email: 'second.audience@example.com',
        email_verified: 'true',
      }),
    );
    createsUser('user-at-second');

    const result = await service.loginWithGoogle({ accessToken: 'ya29.second-client' });

    expect(result.id).toBe('user-at-second');
  });

  it('ignores blank entries rather than treating them as a wildcard', async () => {
    // A trailing comma or a stray space must not widen what is accepted, and an
    // all-blank value must still fail closed.
    configuredClientId = `${CLIENT_ID}, ,`;
    verifyIdTokenMock.mockResolvedValue({ getPayload: () => idTokenPayload() });
    createsUser('user-trailing-comma');

    await service.loginWithGoogle({ idToken: 'real.jwt.token' });
    expect(verifyIdTokenMock).toHaveBeenCalledWith({
      idToken: 'real.jwt.token',
      audience: [CLIENT_ID],
    });

    configuredClientId = ' , ';
    await expect(service.loginWithGoogle({ idToken: 'real.jwt.token' })).rejects.toThrow(
      ServiceUnavailableException,
    );
  });

  it('refuses a disabled account', async () => {
    verifyIdTokenMock.mockResolvedValue({
      getPayload: () => idTokenPayload({ sub: 'banned-sub' }),
    });
    prisma.user.findFirst.mockResolvedValue({
      id: 'user-banned',
      email: 'banned@example.com',
      isActive: false,
      createdAt: new Date(),
      profile: profileOf('user-banned', 'banned@example.com'),
    });

    await expect(service.loginWithGoogle({ idToken: 'real.jwt.token' })).rejects.toThrow(
      UnauthorizedException,
    );

    expect(prisma.session.create).not.toHaveBeenCalled();
  });

  // ── Email trust ────────────────────────────────────────────────────────

  it('does not match a victim by dto.email when the token carries no email claim', async () => {
    verifyIdTokenMock.mockResolvedValue({
      getPayload: () => ({ sub: 'attacker-sub', email_verified: true }),
    });
    createsUser('user-attacker');

    const result = await service.loginWithGoogle({
      idToken: 'real.jwt.token',
      email: 'victim@example.com',
    });

    expect(prisma.user.findFirst).toHaveBeenCalledWith({
      where: { authIdentities: { some: { provider: 'google', providerId: 'attacker-sub' } } },
      include: { profile: true },
    });
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
    expect(result.isNewUser).toBe(true);
    expect(prisma.user.create.mock.calls[0][0].data.email).toBeNull();
  });

  it('will not link by an unverified email address', async () => {
    verifyIdTokenMock.mockResolvedValue({
      getPayload: () => idTokenPayload({ email: 'victim@example.com', email_verified: false }),
    });
    createsUser('user-unverified');

    await service.loginWithGoogle({ idToken: 'real.jwt.token' });

    // The victim's row is never fetched, so it can never be taken over.
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
    expect(prisma.user.create.mock.calls[0][0].data.email).toBeNull();
  });
});
