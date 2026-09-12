import { plainToInstance } from 'class-transformer';
import { IsEnum, IsNumber, IsOptional, IsString, validateSync } from 'class-validator';

export enum Environment {
  Development = 'development',
  Production = 'production',
  Test = 'test',
}

export class EnvironmentVariables {
  @IsEnum(Environment)
  @IsOptional()
  NODE_ENV: Environment = Environment.Development;

  @IsNumber()
  @IsOptional()
  PORT: number = 8080;

  // Database
  @IsString()
  DATABASE_URL: string;

  // Redis
  @IsString()
  REDIS_URL: string;

  // JWT
  @IsString()
  JWT_SECRET: string;

  @IsString()
  @IsOptional()
  JWT_EXPIRES_IN: string = '7d';

  // Google OAuth (optional in dev). Only the client id exists: it is the
  // audience Google credentials are pinned to. There is no client secret here
  // because the client obtains the ID token and this server merely verifies it,
  // so there is no authorization-code exchange for a secret to authorise.
  @IsString()
  @IsOptional()
  GOOGLE_CLIENT_ID: string = '';

// S3-compatible Storage (optional in dev)
  @IsString()
  @IsOptional()
  STORAGE_ENDPOINT: string = 'http://localhost:9000';

  @IsString()
  @IsOptional()
  STORAGE_BUCKET: string = 'sejilo-media';

  /**
   * Public read domain for uploaded objects, without a trailing slash and already
   * pointing at the bucket (an R2 custom domain such as
   * `https://media.sejilochat.com`, or the bucket's `*.r2.dev` URL). Required on
   * R2, where STORAGE_ENDPOINT is the credential-only S3 API host and serves
   * nothing publicly. Empty keeps the dev MinIO `endpoint/bucket/key` layout.
   */
  @IsString()
  @IsOptional()
  STORAGE_PUBLIC_BASE_URL: string = '';

  // S3 credentials are read at runtime by media.service.ts via S3_ACCESS_KEY_ID /
  // S3_SECRET_ACCESS_KEY / S3_REGION / S3_FORCE_PATH_STYLE and are intentionally
  // NOT validated here (empty = presigned uploads disabled).

  // Firebase Cloud Messaging (optional)
  @IsString()
  @IsOptional()
  FCM_PROJECT_ID: string = '';

  @IsString()
  @IsOptional()
  FCM_PRIVATE_KEY: string = '';

  @IsString()
  @IsOptional()
  FCM_CLIENT_EMAIL: string = '';

  // Email / Resend (optional)
  @IsString()
  @IsOptional()
  RESEND_API_KEY: string = '';

  @IsString()
  @IsOptional()
  PASSWORD_RESET_FROM: string = 'SejiloChat <noreply@sejilochat.net>';

  @IsString()
  @IsOptional()
  PASSWORD_RESET_URL: string = 'http://localhost:3000/reset-password';

  // Security
  @IsString()
  @IsOptional()
  TOKEN_PEPPER: string = '';

  /**
   * Comma-separated browser origins allowed to call the API. Supports single-label
   * wildcards (`https://*.trycloudflare.com`). Left empty in production, browser
   * origins are refused outright — see common/config/cors.config.ts.
   */
  @IsString()
  @IsOptional()
  CORS_ORIGIN: string = '';

  /**
   * Set to `true` only when the process sits behind a trusted reverse proxy
   * (Cloudflare Tunnel, nginx, a load balancer). It makes the app believe
   * `CF-Connecting-IP` / `X-Forwarded-For`, which a direct caller could forge.
   */
  @IsString()
  @IsOptional()
  TRUST_PROXY: string = 'false';

  /** `true`/`false`; defaults to enabled outside production. */
  @IsString()
  @IsOptional()
  ENABLE_SWAGGER: string = '';

  @IsString()
  @IsOptional()
  WEB_ALLOWED_ORIGIN: string = '*';

  @IsNumber()
  @IsOptional()
  MAX_CIPHERTEXT_BYTES: number = 196608;

  @IsNumber()
  @IsOptional()
  SESSION_TTL_SECONDS: number = 900;

  @IsNumber()
  @IsOptional()
  REFRESH_TTL_SECONDS: number = 2592000;

  @IsNumber()
  @IsOptional()
  MAX_DEVICE_REQUESTS_PER_MINUTE: number = 300;

  @IsNumber()
  @IsOptional()
  MAX_MESSAGES_PER_MINUTE: number = 60;

  // n8n outbound webhooks (disabled by default)
  @IsString()
  @IsOptional()
  WEBHOOKS_ENABLED: string = 'false';

  @IsString()
  @IsOptional()
  WEBHOOK_SECRET: string = '';

  // Cloudinary media storage (optional; kept server-side only)
  @IsString()
  @IsOptional()
  CLOUDINARY_URL: string = '';

  @IsString()
  @IsOptional()
  CLOUDINARY_CLOUD_NAME: string = '';

  @IsString()
  @IsOptional()
  CLOUDINARY_API_KEY: string = '';

  @IsString()
  @IsOptional()
  CLOUDINARY_API_SECRET: string = '';
}

export function validate(config: Record<string, unknown>) {
  const validatedConfig = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: true,
  });

  const isProd = config['NODE_ENV'] === 'production';
  const errors = validateSync(validatedConfig, { skipMissingProperties: !isProd });

  if (errors.length > 0) {
    const messages = errors
      .map((e) => Object.values(e.constraints ?? {}).join(', '))
      .join('\n');
    throw new Error(
      `\n\n❌  Config validation failed:\n\n${messages}\n\nCheck your .env file.\n`,
    );
  }

  // Critical secrets / connection strings that must always be present,
  // regardless of environment, so the backend never starts half-configured.
  const required = ['DATABASE_URL', 'REDIS_URL', 'JWT_SECRET'] as const;
  const missing = required.filter((key) => {
    const value = (validatedConfig as unknown as Record<string, unknown>)[key];
    return value === undefined || value === null || String(value).trim() === '';
  });
  if (missing.length > 0) {
    throw new Error(
      `\n\n❌  Missing required environment variables: ${missing.join(', ')}\n\nCheck your .env file.\n`,
    );
  }

  // A short or recycled signing key is the difference between "needs a password"
  // and "anyone can mint a token for any account", so it is enforced rather than
  // warned about once the app is exposed beyond localhost.
  if (isProd) {
    const jwtSecret = String(validatedConfig.JWT_SECRET ?? '');
    if (jwtSecret.length < 32) {
      throw new Error(
        '\n\n❌  JWT_SECRET must be at least 32 characters when NODE_ENV=production.\n' +
          '    Generate one with:  node -e "console.log(require(\'crypto\').randomBytes(48).toString(\'base64url\'))"\n',
      );
    }
    const placeholders = ['changeme', 'secret', 'dev', 'test', 'example'];
    if (placeholders.some((p) => jwtSecret.toLowerCase() === p)) {
      throw new Error('\n\n❌  JWT_SECRET is a placeholder value. Set a real secret.\n');
    }
  }

  return validatedConfig;
}
