import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';
import { RecommendationsService } from './recommendations.service';

@Module({
  imports: [ScheduleModule.forRoot()],
  controllers: [UsersController],
  providers: [UsersService, RecommendationsService],
  exports: [UsersService, RecommendationsService],
})
export class UsersModule {}
