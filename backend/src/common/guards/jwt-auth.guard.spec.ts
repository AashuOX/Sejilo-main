import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { JwtAuthGuard } from './jwt-auth.guard';

/**
 * These cover the regression that made every viewer-aware public route behave
 * as if nobody was signed in: the guard used to `return true` for `@Public()`
 * before Passport ran, so `request.user` was never populated and the block /
 * private-account filtering in explore, search, the profile grid and comments
 * silently did nothing.
 */
describe('JwtAuthGuard', () => {
  const contextFor = (): ExecutionContext =>
    ({
      getHandler: () => function handler() {},
      getClass: () => class Controller {},
      switchToHttp: () => ({ getRequest: () => ({}), getResponse: () => ({}) }),
    }) as unknown as ExecutionContext;

  const guardWith = (isPublic: boolean) => {
    const reflector = {
      getAllAndOverride: jest.fn().mockReturnValue(isPublic),
    } as unknown as Reflector;
    return new JwtAuthGuard(reflector);
  };

  const VIEWER = { userId: 'ffffffff-ffff-ffff-ffff-ffffffffffff' };

  describe('a public route authenticates optionally', () => {
    it('still runs the strategy instead of short-circuiting', async () => {
      // The whole point of the fix: a bearer token on a public route has to be
      // read, which cannot happen if canActivate returns before Passport.
      const parent = Object.getPrototypeOf(JwtAuthGuard.prototype);
      const parentCanActivate = jest
        .spyOn(parent as InstanceType<ReturnType<typeof AuthGuard>>, 'canActivate')
        .mockResolvedValue(true);

      await expect(guardWith(true).canActivate(contextFor())).resolves.toBe(
        true,
      );
      expect(parentCanActivate).toHaveBeenCalled();

      parentCanActivate.mockRestore();
    });

    it('hands the viewer through when the token is good', () => {
      expect(
        guardWith(true).handleRequest(null, VIEWER, undefined, contextFor()),
      ).toEqual(VIEWER);
    });

    it('falls back to anonymous when there is no token', () => {
      expect(
        guardWith(true).handleRequest(
          null,
          false,
          { message: 'No auth token' },
          contextFor(),
        ),
      ).toBeUndefined();
    });

    it('falls back to anonymous on an expired or revoked token rather than 401', () => {
      // A stale token must not lock somebody out of a page anyone can read.
      expect(
        guardWith(true).handleRequest(
          new UnauthorizedException('Session has been revoked or expired'),
          false,
          undefined,
          contextFor(),
        ),
      ).toBeUndefined();
    });
  });

  describe('a guarded route is unchanged', () => {
    it('rejects a missing token', () => {
      expect(() =>
        guardWith(false).handleRequest(null, false, undefined, contextFor()),
      ).toThrow(UnauthorizedException);
    });

    it('propagates the strategy error', () => {
      const failure = new UnauthorizedException('User not found or inactive');
      expect(() =>
        guardWith(false).handleRequest(failure, false, undefined, contextFor()),
      ).toThrow(failure);
    });

    it('passes a valid user through', () => {
      expect(
        guardWith(false).handleRequest(null, VIEWER, undefined, contextFor()),
      ).toEqual(VIEWER);
    });
  });
});
