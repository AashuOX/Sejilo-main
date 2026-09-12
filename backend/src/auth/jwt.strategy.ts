import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';

export interface JwtPayload {
  sub: string;
  userId: string;
  email: string | null;
  sessionId?: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_SECRET'),
      passReqToCallback: true,
    });
  }

  async validate(req: any, payload: JwtPayload) {
    const userId = payload.sub || payload.userId;
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { profile: true },
    });

    if (!user || !user.isActive) {
      throw new UnauthorizedException('User not found or inactive');
    }

    // Check session revocation — extract the raw token and verify it's not revoked
    if (payload.sessionId) {
      const rawToken = req.headers?.authorization?.replace(/^Bearer /i, '');
      if (rawToken) {
        const tokenHash = createHash('sha256').update(rawToken).digest('hex');
        const session = await this.prisma.session.findFirst({
          where: {
            tokenHash,
            userId,
            revokedAt: null,
            expiresAt: { gt: new Date() },
          },
        });

        if (!session) {
          throw new UnauthorizedException('Session has been revoked or expired');
        }
      }
    }

    return {
      id: user.id,
      userId: user.id,
      email: user.email,
      username: user.profile?.username ?? '',
      displayName: user.profile?.displayName ?? '',
      avatarUrl: user.profile?.avatarUrl,
      sessionId: payload.sessionId,
    };
  }
}

