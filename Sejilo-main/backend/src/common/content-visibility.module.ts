import { Global, Module } from '@nestjs/common';
import { ContentVisibilityService } from './content-visibility.service';

/// Global for the same reason `PrismaModule` is: every feature module that
/// serves someone else's content needs this check, and a module that has to
/// remember to import it is a module that can forget.
@Global()
@Module({
  providers: [ContentVisibilityService],
  exports: [ContentVisibilityService],
})
export class ContentVisibilityModule {}
