import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { WsAdapter } from '@nestjs/platform-ws';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import * as dotenv from 'dotenv';
import { json, urlencoded } from 'express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { buildCorsPolicy } from './common/config/cors.config';

// CORS, trust-proxy and Swagger gating are decided before NestFactory.create(),
// which is also when ConfigModule would normally load the .env file - so load it
// here first. Same file order as ConfigModule, and dotenv never overwrites a
// variable that is already set in the real environment.
dotenv.config({ path: ['.env', '.env.local'] });

async function bootstrap() {
  const logger = new Logger('SejiloChatBackend');
  const isProduction = process.env.NODE_ENV === 'production';
  const cors = buildCorsPolicy();

  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    cors: cors.options,
    // Registered by hand below so the size limit is explicit. Express defaults
    // to 100 KB, which — after base64url inflates bytes by 4/3 — rejected any
    // image over ~73 KB with a bare 413 and no usable message.
    bodyParser: false,
  });

  // Comfortably above MAX_MEDIA_BASE64_LENGTH so an oversized upload is caught
  // by DTO validation, which can name the real limit, instead of dying here.
  app.use(json({ limit: '4mb' }));
  app.use(urlencoded({ extended: true, limit: '4mb' }));

  // Behind Cloudflare Tunnel / any reverse proxy the socket address is always
  // loopback. Trusting one proxy hop restores the real client IP for rate
  // limiting and logging. Off by default: when the port is reachable directly,
  // clients can forge forwarding headers.
  const trustProxy = (process.env.TRUST_PROXY ?? '').toLowerCase() === 'true';
  app.set('trust proxy', trustProxy ? 1 : false);

  // Security headers (STEP 27 — Security Audit)
  app.use(helmet());

  // Enable WebSockets via ws adapter
  app.useWebSocketAdapter(new WsAdapter(app));

  // Global Input Validation & Sanitization
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: false,
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  // OpenAPI / Swagger Documentation.
  // Publishing the full API surface (every route, DTO shape and validation rule)
  // to anonymous callers is free reconnaissance, so it is off by default once
  // NODE_ENV=production. Set ENABLE_SWAGGER=true to override deliberately.
  const swaggerEnabled = process.env.ENABLE_SWAGGER
    ? process.env.ENABLE_SWAGGER.toLowerCase() === 'true'
    : !isProduction;

  if (swaggerEnabled) {
    const swaggerConfig = new DocumentBuilder()
      .setTitle('SejiloChat API')
      .setDescription(
        'Official Production REST & Real-Time API for SejiloChat.\n' +
        'Supports Authentication, Social Feeds, Stories, Follows, Conversations, Direct & Group Messaging, Media, and Offline Sync.',
      )
      .setVersion('1.0.0')
      .addBearerAuth(
        {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT',
          name: 'JWT',
          description: 'Enter your JWT access token',
          in: 'header',
        },
        'JWT',
      )
      .addTag('Authentication', 'User registration, email/password login, Google OAuth, session management')
      .addTag('Users & Profiles', 'User profile management, search, and public profile lookups')
      .addTag('Social Follows', 'Followers, following, and follow status management')
      .addTag('Posts, Feeds & Comments', 'Chronological feed, explore grid, post creation, likes, and comment threads')
      .addTag('Stories (24h Ephemeral)', 'Ephemeral media and text stories with 24-hour expiration and view tracking')
      .addTag('Chat & Real-Time Messaging', '1-on-1 direct and group conversations, messages, read receipts, and reactions')
      .addTag('Media & Uploads', 'S3-compatible presigned upload URLs and media metadata retrieval')
      .addTag('Sync Engine (Offline-First)', 'Incremental cursor-based synchronization and offline outbox reconciliation')
      .addTag('Health & Monitoring', 'Liveness, readiness, and service health check endpoints')
      .build();

    const document = SwaggerModule.createDocument(app, swaggerConfig);
    SwaggerModule.setup('api/docs', app, document);
    SwaggerModule.setup('docs', app, document);
  }

  // Enable Graceful Shutdown
  app.enableShutdownHooks();

  const port = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
  await app.listen(port, '0.0.0.0');

  logger.log(`=======================================================`);
  logger.log(`  SejiloChat Backend running on port ${port}`);
  logger.log(`  Environment:  ${process.env.NODE_ENV ?? 'development'}`);
  logger.log(`  CORS:         ${cors.summary}`);
  logger.log(`  Trust proxy:  ${trustProxy ? 'yes (1 hop)' : 'no'}`);
  logger.log(`  Swagger UI:   ${swaggerEnabled ? `http://localhost:${port}/api/docs` : 'disabled'}`);
  logger.log(`  Health Check: http://localhost:${port}/health`);
  logger.log(`  WebSocket:    ws://localhost:${port}/v1/chat/ws`);
  logger.log(`=======================================================`);
}

bootstrap().catch((err) => {
  console.error('Fatal bootstrap error:', err);
  process.exit(1);
});
