import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MediaService } from './media.service';

@ApiTags('Media & Uploads')
@Controller('v1/media')
export class MediaController {
  constructor(private readonly mediaService: MediaService) {}

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Post('upload-url')
  @ApiOperation({ summary: 'Request authorized upload URL for media asset' })
  async requestUploadUrl(
    @CurrentUser('userId') userId: string,
    @Body() body: { filename: string; mimeType: string; sizeBytes: number },
  ) {
    return this.mediaService.createUploadUrl(
      userId,
      body.filename,
      body.mimeType,
      body.sizeBytes,
    );
  }

  @Get(':mediaId')
  @ApiOperation({ summary: 'Get metadata for media asset' })
  async getMedia(@Param('mediaId') mediaId: string) {
    return this.mediaService.getMedia(mediaId);
  }
}
