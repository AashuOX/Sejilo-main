import { Logger } from '@nestjs/common';
import type { CorsOptions } from '@nestjs/common/interfaces/external/cors-options.interface';

const logger = new Logger('CorsPolicy');

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Turns a wildcard origin such as `https://*.trycloudflare.com` into a matcher.
 * `*` stands in for a single hostname label only, so it can never widen to a
 * different registrable domain (`https://evil.com/?x=.trycloudflare.com`).
 */
function toPattern(origin: string): RegExp {
  const parts = origin.split('*').map(escapeRegExp);
  return new RegExp(`^${parts.join('[^./]*')}$`, 'i');
}

export interface CorsPolicy {
  options: CorsOptions;
  /** Human-readable summary for the startup banner. */
  summary: string;
}

/**
 * Builds the CORS policy from `CORS_ORIGIN` (comma-separated; `*` and wildcard
 * subdomains supported).
 *
 * Reflecting an arbitrary origin while `credentials: true` is set lets any
 * website read authenticated responses on behalf of a logged-in visitor, so in
 * production an unset or wildcard `CORS_ORIGIN` fails closed: browser origins
 * are refused rather than reflected. Requests without an `Origin` header —
 * native mobile clients, curl, server-to-server — are unaffected, since CORS
 * is a browser-enforced policy and never applied to them.
 */
export function buildCorsPolicy(env: NodeJS.ProcessEnv = process.env): CorsPolicy {
  const isProduction = env.NODE_ENV === 'production';
  const configured = (env.CORS_ORIGIN ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

  const wantsWildcard = configured.length === 0 || configured.includes('*');
  const exact = new Set(
    configured.filter((o) => o !== '*' && !o.includes('*')).map((o) => o.toLowerCase()),
  );
  const patterns = configured.filter((o) => o !== '*' && o.includes('*')).map(toPattern);

  let allowAnyOrigin = wantsWildcard;
  let summary: string;

  if (wantsWildcard && isProduction) {
    allowAnyOrigin = false;
    logger.warn(
      'CORS_ORIGIN is unset or "*" while NODE_ENV=production — refusing all browser ' +
        'origins. Native app and server-to-server traffic still works. Set CORS_ORIGIN ' +
        'to your web origins (wildcards allowed, e.g. https://*.trycloudflare.com) to ' +
        'enable browser clients.',
    );
    summary = 'production fail-closed (no browser origins allowed)';
  } else if (allowAnyOrigin) {
    logger.warn('CORS is reflecting any origin — development only.');
    summary = 'any origin (development)';
  } else {
    summary = configured.join(', ');
  }

  const options: CorsOptions = {
    origin: (origin, callback) => {
      // No Origin header: not a browser cross-origin request, nothing to police.
      if (!origin) {
        return callback(null, true);
      }
      if (allowAnyOrigin) {
        return callback(null, true);
      }
      const candidate = origin.toLowerCase();
      if (exact.has(candidate) || patterns.some((pattern) => pattern.test(origin))) {
        return callback(null, true);
      }
      // `false` omits the CORS headers so the browser blocks it, rather than
      // raising a 500 the way returning an Error would.
      return callback(null, false);
    },
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
    allowedHeaders: 'Content-Type, Accept, Authorization',
    maxAge: 86400,
  };

  return { options, summary };
}
