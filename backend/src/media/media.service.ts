import { Injectable, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { v2 as cloudinary } from 'cloudinary';
import { PrismaService } from '../prisma/prisma.service';
import { WebhooksService } from '../webhooks/webhooks.service';

const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'video/mp4',
  'video/quicktime',
  'audio/mp4',
  'audio/m4a',
  'audio/aac',
  'audio/mpeg',
  'audio/wav',
]);

const MAX_FILE_SIZE_BYTES = 50 * 1024 * 1024; // 50MB

@Injectable()
export class MediaService {
  private readonly storageEndpoint: string;
  private readonly storagePublicBaseUrl: string;
  private readonly storageBucket: string;
  private readonly region: string;
  private readonly accessKeyId: string;
  private readonly secretAccessKey: string;
  private readonly forcePathStyle: boolean;
  private readonly s3: S3Client | null = null;
  private readonly cloudinaryCloudName: string | null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly webhooks: WebhooksService,
  ) {
    this.storageEndpoint = this.config.get<string>('STORAGE_ENDPOINT', 'http://localhost:9000');
    // On Cloudflare R2 (and most managed object stores) the S3 API endpoint is
    // credential-only and serves nothing to the public, so a URL built from it
    // would 401 in the app. STORAGE_PUBLIC_BASE_URL is the separate read domain
    // - an R2 custom domain or *.r2.dev - and already includes the bucket, so
    // the object key is appended directly. Empty falls back to the MinIO-style
    // endpoint/bucket/key layout used in development.
    this.storagePublicBaseUrl = this.config
      .get<string>('STORAGE_PUBLIC_BASE_URL', '')
      .trim()
      .replace(/\/+$/, '');
    this.storageBucket = this.config.get<string>('STORAGE_BUCKET', 'sejilo-media');
    this.region = this.config.get<string>('S3_REGION', 'us-east-1');
    this.accessKeyId = this.config.get<string>('S3_ACCESS_KEY_ID', '');
    this.secretAccessKey = this.config.get<string>('S3_SECRET_ACCESS_KEY', '');
    this.forcePathStyle = this.config.get<string>('S3_FORCE_PATH_STYLE', 'true') === 'true';
    this.cloudinaryCloudName = this.configureCloudinary();

    if (this.accessKeyId && this.secretAccessKey) {
      this.s3 = new S3Client({
        region: this.region,
        endpoint: this.storageEndpoint,
        forcePathStyle: this.forcePathStyle,
        credentials: {
          accessKeyId: this.accessKeyId,
          secretAccessKey: this.secretAccessKey,
        },
      });
    }
  }

  /** Configure Cloudinary from CLOUDINARY_URL or explicit server-only keys. */
  private configureCloudinary(): string | null {
    const cloudinaryUrl = this.config.get<string>('CLOUDINARY_URL', '').trim();
    const cloudName = this.config.get<string>('CLOUDINARY_CLOUD_NAME', '').trim();
    const apiKey = this.config.get<string>('CLOUDINARY_API_KEY', '').trim();
    const apiSecret = this.config.get<string>('CLOUDINARY_API_SECRET', '').trim();

    if (cloudinaryUrl) {
      try {
        const parsed = new URL(cloudinaryUrl);
        if (parsed.protocol !== 'cloudinary:' || !parsed.hostname || !parsed.username || !parsed.password) {
          throw new Error('invalid Cloudinary URL');
        }
        cloudinary.config({
          cloud_name: parsed.hostname,
          api_key: decodeURIComponent(parsed.username),
          api_secret: decodeURIComponent(parsed.password),
          secure: true,
        });
        return parsed.hostname;
      } catch {
        throw new BadRequestException('CLOUDINARY_URL must use cloudinary://<api-key>:<api-secret>@<cloud-name>.');
      }
    }

    if (cloudName && apiKey && apiSecret) {
      cloudinary.config({ cloud_name: cloudName, api_key: apiKey, api_secret: apiSecret, secure: true });
      return cloudName;
    }
    return null;
  }

  async createUploadUrl(userId: string, filename: string, mimeType: string, sizeBytes: number) {
    if (!ALLOWED_MIME_TYPES.has(mimeType.toLowerCase())) {
      throw new BadRequestException(`Unsupported media MIME type: ${mimeType}`);
    }

    if (sizeBytes > MAX_FILE_SIZE_BYTES) {
      throw new BadRequestException(`File exceeds maximum size limit of ${MAX_FILE_SIZE_BYTES / (1024 * 1024)}MB`);
    }

    const mediaId = randomUUID();
    const ext = filename.split('.').pop() || 'bin';
    const storageKey = `uploads/${userId}/${mediaId}.${ext}`;
    const cloudinaryResourceType = mimeType.startsWith('video')
      ? 'video'
      : mimeType.startsWith('image')
        ? 'image'
        : 'raw';
    const cloudinaryPublicId = `sejilo/${userId}/${mediaId}`;
    const objectPublicUrl = this.storagePublicBaseUrl
      ? `${this.storagePublicBaseUrl}/${storageKey}`
      : `${this.storageEndpoint}/${this.storageBucket}/${storageKey}`;
    const publicUrl = this.cloudinaryCloudName
      ? cloudinary.url(cloudinaryPublicId, {
          resource_type: cloudinaryResourceType,
          secure: true,
          ...(cloudinaryResourceType === 'image' ? { fetch_format: 'auto', quality: 'auto' } : {}),
        })
      : objectPublicUrl;

    // Presigned PUT URL when S3 credentials are configured; otherwise fall back
    // to the legacy direct URL (MinIO console/dev setups without credentials).
    let uploadUrl = publicUrl;
    const expiresInSeconds = 3600;
    let uploadMethod: 'PUT' | 'POST' = 'PUT';
    let uploadParams: Record<string, string | number> | undefined;
    if (this.cloudinaryCloudName) {
      const timestamp = Math.floor(Date.now() / 1000);
      const signature = cloudinary.utils.api_sign_request(
        { public_id: cloudinaryPublicId, timestamp },
        cloudinary.config().api_secret!,
      );
      uploadUrl = `https://api.cloudinary.com/v1_1/${this.cloudinaryCloudName}/${cloudinaryResourceType}/upload`;
      uploadMethod = 'POST';
      uploadParams = {
        api_key: cloudinary.config().api_key!,
        timestamp,
        signature,
        public_id: cloudinaryPublicId,
      };
    } else if (this.s3) {
      uploadUrl = await getSignedUrl(
        this.s3,
        new PutObjectCommand({
          Bucket: this.storageBucket,
          Key: storageKey,
          ContentType: mimeType,
          ContentLength: sizeBytes,
        }),
        { expiresIn: expiresInSeconds },
      );
    }

    const media = await this.prisma.media.create({
      data: {
        id: mediaId,
        userId,
        filename,
        mimeType,
        sizeBytes: BigInt(sizeBytes),
        storageKey,
        url: publicUrl,
        type: mimeType.startsWith('video') ? 'video' : mimeType.startsWith('audio') ? 'audio' : 'image',
      },
    });

    await this.webhooks.onMediaUploaded({
      mediaId: media.id,
      userId,
      type: media.type as 'image' | 'video' | 'audio' | 'document',
      size: Number(media.sizeBytes),
      mimeType: media.mimeType,
      createdAt: media.createdAt.toISOString(),
    });

    return {
      mediaId: media.id,
      uploadUrl,
      publicUrl,
      storageKey,
      expiresInSeconds,
      presigned: this.s3 !== null,
      provider: this.cloudinaryCloudName ? 'cloudinary' : 's3',
      uploadMethod,
      uploadParams,
    };
  }

  async getMedia(mediaId: string) {
    const media = await this.prisma.media.findUnique({ where: { id: mediaId } });
    if (!media) return null;

    return {
      id: media.id,
      userId: media.userId,
      filename: media.filename,
      mimeType: media.mimeType,
      sizeBytes: Number(media.sizeBytes),
      url: media.url,
      type: media.type,
      createdAt: media.createdAt.toISOString(),
    };
  }
}
