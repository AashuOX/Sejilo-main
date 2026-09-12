import { Controller, Get, HttpStatus, Res } from '@nestjs/common';
import { ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import { Public } from '../common/decorators/public.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

@ApiTags('Health & Monitoring')
@Controller()
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  @Public()
  @Get('health')
  @ApiOperation({ summary: 'Basic health check endpoint' })
  @ApiResponse({ status: 200, description: 'Service is healthy' })
  getHealth() {
    return {
      status: 'ok',
      service: 'SejiloChat Production Backend',
      version: '1.0.0',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
    };
  }

  @Public()
  @Get('health/live')
  @ApiOperation({ summary: 'Kubernetes/Docker liveness probe' })
  getLiveness() {
    return { status: 'ok' };
  }

  @Public()
  @Get('health/ready')
  @ApiOperation({ summary: 'Kubernetes/Docker readiness probe (PostgreSQL & Redis)' })
  async getReadiness(@Res() res: Response) {
    let dbStatus = 'ok';
    let redisStatus = 'ok';

    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch (e) {
      dbStatus = 'unavailable';
    }

    try {
      const client = this.redis.getClient();
      if (client) {
        await client.ping();
      } else {
        redisStatus = 'disabled';
      }
    } catch (e) {
      redisStatus = 'unavailable';
    }

    const isReady = dbStatus === 'ok' && (redisStatus === 'ok' || redisStatus === 'disabled');
    const statusCode = isReady ? HttpStatus.OK : HttpStatus.SERVICE_UNAVAILABLE;

    return res.status(statusCode).json({
      status: isReady ? 'ok' : 'degraded',
      database: dbStatus,
      redis: redisStatus,
      timestamp: new Date().toISOString(),
    });
  }
}
