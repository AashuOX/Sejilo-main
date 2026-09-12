import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiResponse, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { AuthService } from './auth.service';
import { GoogleLoginDto } from './dto/google-login.dto';
import { LoginDto } from './dto/login.dto';
import { PasswordResetConfirmDto } from './dto/password-reset-confirm.dto';
import { PasswordResetRequestDto } from './dto/password-reset-request.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { RegisterDto } from './dto/register.dto';
import { SendPhoneOtpDto } from './dto/send-phone-otp.dto';
import { VerifyPhoneOtpDto } from './dto/verify-phone-otp.dto';

/**
 * Per-route rate limits, tighter than the global 120/min tier.
 *
 * These are the endpoints an unauthenticated caller on the public internet can
 * reach, so they are the ones worth budgeting individually: credential stuffing
 * against login, enumeration via register, and the two endpoints that spend real
 * money per call (SMS and email delivery).
 */
const LOGIN_LIMIT = { default: { limit: 10, ttl: 60_000 } };
const REGISTER_LIMIT = { default: { limit: 5, ttl: 60_000 } };
const OTP_LIMIT = { default: { limit: 3, ttl: 60_000 } };
const RESET_REQUEST_LIMIT = { default: { limit: 3, ttl: 60_000 } };
const REFRESH_LIMIT = { default: { limit: 30, ttl: 60_000 } };

@ApiTags('Authentication')
@Controller()
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Throttle(REGISTER_LIMIT)
  @Post(['v1/users', 'v1/auth/register'])
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Register a new user with email and password' })
  @ApiResponse({ status: 201, description: 'User successfully registered' })
  @ApiResponse({ status: 409, description: 'Email or username already exists' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Public()
  @Throttle(LOGIN_LIMIT)
  @Post(['v1/auth/password/login', 'v1/auth/login'])
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Authenticate user with email and password' })
  @ApiResponse({ status: 200, description: 'Login successful' })
  @ApiResponse({ status: 401, description: 'Invalid credentials' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Public()
  @Throttle(LOGIN_LIMIT)
  @Post('v1/auth/google')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Authenticate with Google ID or access token' })
  @ApiResponse({ status: 200, description: 'Google authentication successful' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async googleLogin(@Body() dto: GoogleLoginDto) {
    return this.authService.loginWithGoogle(dto);
  }

  @Public()
  @Throttle(REFRESH_LIMIT)
  @Post('v1/auth/refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Refresh an expired access token' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async refreshToken(@Body() dto: RefreshTokenDto) {
    return this.authService.refreshToken(dto.refreshToken);
  }

  @Public()
  @Throttle(OTP_LIMIT)
  @Post('v1/auth/phone/otp-requests')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Request a one-time SMS verification code for a phone number' })
  @ApiResponse({ status: 200, description: 'OTP accepted for delivery' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async requestPhoneOtp(@Body() dto: SendPhoneOtpDto) {
    return this.authService.requestPhoneOtp(dto.phoneNumber);
  }

  @Public()
  @Throttle(LOGIN_LIMIT)
  @Post('v1/auth/phone/verify')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Verify a phone OTP and sign in (or register) the user' })
  @ApiResponse({ status: 200, description: 'Authenticated successfully' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async verifyPhoneOtp(@Body() dto: VerifyPhoneOtpDto) {
    return this.authService.verifyPhoneOtp(dto);
  }

  @Public()
  @Throttle(RESET_REQUEST_LIMIT)
  @Post('v1/auth/password/reset-requests')
  @HttpCode(HttpStatus.ACCEPTED)
  @ApiOperation({ summary: 'Request a password reset email' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async requestPasswordReset(@Body() dto: PasswordResetRequestDto) {
    return this.authService.requestPasswordReset(dto.email);
  }

  @Public()
  @Throttle(LOGIN_LIMIT)
  @Post('v1/auth/password/resets')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Confirm password reset with token' })
  @ApiResponse({ status: 429, description: 'Too many requests' })
  async resetPassword(@Body() dto: PasswordResetConfirmDto) {
    await this.authService.resetPassword(dto.token, dto.newPassword);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete(['v1/auth/password/session', 'v1/auth/logout'])
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Log out current session' })
  async logout(@CurrentUser('userId') userId: string, @CurrentUser('sessionId') sessionId?: string) {
    await this.authService.logout(userId, sessionId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Delete('v1/me')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Permanently delete user account' })
  async deleteAccount(@CurrentUser('userId') userId: string) {
    await this.authService.deleteAccount(userId);
  }
}
