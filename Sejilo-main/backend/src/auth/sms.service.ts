import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Pluggable SMS delivery for phone OTP codes.
 *
 * A real SMS provider (Twilio, Vonage, etc.) can be wired in by setting
 * SMS_PROVIDER and the matching credentials in .env. Until then, codes are
 * logged to the server console in development so flows remain testable.
 */
@Injectable()
export class SmsService {
  private readonly logger = new Logger(SmsService.name);
  private readonly provider: string;
  private readonly accountSid: string;
  private readonly authToken: string;
  private readonly fromNumber: string;

  constructor(private readonly config: ConfigService) {
    this.provider = this.config.get<string>('SMS_PROVIDER', '').toLowerCase();
    this.accountSid = this.config.get<string>('SMS_ACCOUNT_SID', '');
    this.authToken = this.config.get<string>('SMS_AUTH_TOKEN', '');
    this.fromNumber = this.config.get<string>('SMS_FROM_NUMBER', '');
  }

  get isConfigured(): boolean {
    return (
      this.provider === 'twilio' &&
      Boolean(this.accountSid && this.authToken && this.fromNumber)
    );
  }

  async sendOtp(phoneNumber: string, code: string): Promise<void> {
    if (this.isConfigured && this.provider === 'twilio') {
      try {
        const res = await fetch(
          `https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Messages.json`,
          {
            method: 'POST',
            headers: {
              Authorization:
                'Basic ' +
                Buffer.from(`${this.accountSid}:${this.authToken}`).toString(
                  'base64',
                ),
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({
              To: phoneNumber,
              From: this.fromNumber,
              Body: `Your SejiloChat verification code is ${code}. It expires in 5 minutes.`,
            }),
          },
        );
        if (!res.ok) {
          const body = await res.text();
          this.logger.error(`Twilio SMS failed (${res.status}): ${body}`);
          return;
        }
        this.logger.log(`OTP sent to ${phoneNumber} via Twilio`);
        return;
      } catch (err) {
        this.logger.error(
          `Failed to send OTP via Twilio: ${(err as Error).message}`,
        );
        return;
      }
    }

    this.logger.warn(
      `[DEV] SejiloChat OTP for ${phoneNumber}: ${code}\n` +
        `  Set SMS_PROVIDER/SMS_ACCOUNT_SID/SMS_AUTH_TOKEN/SMS_FROM_NUMBER in .env to send real SMS.`,
    );
  }
}