import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CreateReportDto } from './dto/create-report.dto';
import { ReportsService } from './reports.service';

/**
 * Filing is cheap for an honest user — a handful a minute is already more than
 * anyone reports by hand — and cheap abuse is exactly how a moderation table
 * gets flooded.
 */
const REPORT_LIMIT = { default: { limit: 10, ttl: 60_000 } };

@ApiTags('Reports')
@Controller()
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle(REPORT_LIMIT)
  @Post('v1/users/:idOrUsername/reports')
  @ApiOperation({ summary: 'Report a user account' })
  async reportUser(
    @CurrentUser('userId') userId: string,
    @Param('idOrUsername') idOrUsername: string,
    @Body() dto: CreateReportDto,
  ) {
    return this.reportsService.reportUser(userId, idOrUsername, dto);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle(REPORT_LIMIT)
  @Post('v1/posts/:postId/reports')
  @ApiOperation({ summary: 'Report a post' })
  async reportPost(
    @CurrentUser('userId') userId: string,
    @Param('postId') postId: string,
    @Body() dto: CreateReportDto,
  ) {
    return this.reportsService.reportPost(userId, postId, dto);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('v1/me/reports')
  @ApiOperation({ summary: 'List the reports you have filed' })
  @ApiQuery({ name: 'limit', required: false, description: 'Max records (default 50, max 100)' })
  async listMyReports(@CurrentUser('userId') userId: string, @Query('limit') limit?: string) {
    return this.reportsService.listMyReports(userId, limit ? parseInt(limit, 10) || 50 : 50);
  }
}
