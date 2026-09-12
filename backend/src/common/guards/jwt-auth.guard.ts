import { ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private reflector: Reflector) {
    super();
  }

  private isPublic(context: ExecutionContext): boolean {
    return (
      this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
        context.getHandler(),
        context.getClass(),
      ]) ?? false
    );
  }

  /**
   * A `@Public()` route is not "anonymous", it is "signed in optionally".
   *
   * This used to `return true` before Passport ran, so `request.user` stayed
   * empty even when the caller sent a perfectly good bearer token. Every public
   * route that takes an optional viewer — explore, the profile grid, a post's
   * comments, user search, a public profile — therefore received
   * `viewerId: undefined` for signed-in users, and the block and private-account
   * filtering those handlers apply was dead code in production: a blocked
   * account still turned up in search and in the explore grid.
   *
   * Now the strategy always runs; [handleRequest] is what decides whether a
   * missing or invalid token is fatal.
   */
  canActivate(context: ExecutionContext) {
    return super.canActivate(context);
  }

  /**
   * On a public route a failed or absent token means "treat this caller as
   * anonymous", not 401. On every other route the usual behaviour stands.
   */
  handleRequest<TUser = any>(
    err: any,
    user: any,
    info: any,
    context: ExecutionContext,
    status?: any,
  ): TUser {
    if (this.isPublic(context)) {
      return (user || undefined) as TUser;
    }
    return super.handleRequest(err, user, info, context, status);
  }
}
