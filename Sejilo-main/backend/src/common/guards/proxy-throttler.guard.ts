import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/**
 * Rate-limit tracker that survives being placed behind a reverse proxy.
 *
 * When the backend is reached through Cloudflare Tunnel (or any proxy), every
 * request arrives on the loopback interface, so the default `req.ip` tracker
 * collapses the entire internet into a single rate-limit bucket: one noisy
 * client would throttle every real user.
 *
 * Forwarded headers are only honoured when `TRUST_PROXY=true`, because a client
 * that can reach the origin directly is free to forge them and thereby dodge
 * rate limiting entirely.
 */
@Injectable()
export class ProxyAwareThrottlerGuard extends ThrottlerGuard {
  private trustProxy?: boolean;

  /**
   * Resolved on first use rather than at class-load time: the class is imported
   * before ConfigModule has read the .env file into process.env.
   */
  private isProxyTrusted(): boolean {
    if (this.trustProxy === undefined) {
      this.trustProxy = (process.env.TRUST_PROXY ?? '').toLowerCase() === 'true';
    }
    return this.trustProxy;
  }

  protected async getTracker(req: Record<string, any>): Promise<string> {
    if (this.isProxyTrusted()) {
      // Set by the Cloudflare edge and not forgeable through the tunnel.
      const cfIp = this.firstHeader(req, 'cf-connecting-ip');
      if (cfIp) {
        return cfIp;
      }

      // Left-most entry is the original client for a single trusted proxy hop.
      const forwardedFor = this.firstHeader(req, 'x-forwarded-for');
      if (forwardedFor) {
        const client = forwardedFor.split(',')[0]?.trim();
        if (client) {
          return client;
        }
      }
    }

    return req?.ip ?? req?.socket?.remoteAddress ?? 'unknown';
  }

  private firstHeader(req: Record<string, any>, name: string): string | undefined {
    const raw = req?.headers?.[name];
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (typeof value !== 'string') {
      return undefined;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  }
}
