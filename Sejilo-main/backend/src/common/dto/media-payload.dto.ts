import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, Matches, MaxLength } from 'class-validator';

/**
 * Largest media payload the API accepts, measured on the base64url string.
 *
 * The body-parser limit in main.ts is deliberately set a little above this so
 * that an oversized upload fails here — as a 400 naming the real ceiling —
 * rather than as Express's bare "request entity too large" 413, which gives the
 * client nothing to show the user.
 *
 * base64 costs 4 bytes per 3, so this is ~2.25 MB of actual image data. That is
 * comfortably more than the client produces after `ImageUtils.optimizeImageBytes`
 * downscales to 1080px and encodes JPEG, while staying small enough that a
 * handful of concurrent uploads cannot exhaust a 512 MB free-tier instance.
 */
export const MAX_MEDIA_BASE64_LENGTH = 3 * 1024 * 1024;

/** Formats the storage layer can actually serve back to a client. */
const ALLOWED_MIME =
  /^(image\/(jpeg|png|webp|gif)|video\/(mp4|webm|quicktime))$/;

/**
 * A single inline media payload.
 *
 * Every field is validated because these values are used unguarded downstream:
 * `data` goes straight into `Buffer.from(…, 'base64url')` and `mimeType` into
 * `.startsWith('video')`. Declaring the shape without `@ValidateNested` — as the
 * three media DTOs originally did — let any non-empty value through validation
 * and turned a malformed upload into a 500.
 */
export class MediaPayloadDto {
  @ApiProperty({ example: 'image/jpeg', description: 'MIME type of the payload' })
  @IsString()
  // Messages are phrased to read correctly after class-validator's nested
  // prefix, which turns them into "media.mimeType is required." and so on.
  @IsNotEmpty({ message: 'mimeType is required.' })
  @Matches(ALLOWED_MIME, {
    message:
      'mimeType is not a supported media type. Allowed: image/jpeg, image/png, image/webp, image/gif, video/mp4, video/webm, video/quicktime.',
  })
  mimeType: string;

  @ApiProperty({ description: 'base64url-encoded media bytes' })
  @IsString()
  @IsNotEmpty({ message: 'data is required.' })
  @MaxLength(MAX_MEDIA_BASE64_LENGTH, {
    message: 'data is too large — the limit is about 2 MB per image or video.',
  })
  @Matches(/^[A-Za-z0-9_-]+=*$/, {
    message: 'data must be base64url-encoded (no data: URL prefix).',
  })
  data: string;
}
