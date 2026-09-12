import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);
  private readonly resendApiKey: string;
  private readonly fromAddress: string;
  private readonly resetUrl: string;

  constructor(private readonly config: ConfigService) {
    this.resendApiKey = this.config.get<string>('RESEND_API_KEY', '');
    this.fromAddress = this.config.get<string>(
      'PASSWORD_RESET_FROM',
      'SejiloChat <noreply@sejilochat.net>',
    );
    this.resetUrl = this.config.get<string>(
      'PASSWORD_RESET_URL',
      'http://localhost:3000/reset-password',
    );
  }

  async sendPasswordResetEmail(email: string, token: string): Promise<void> {
    const link = `${this.resetUrl}?token=${encodeURIComponent(token)}`;

    if (!this.resendApiKey) {
      this.logger.warn(
        `[DEV] Password reset link for ${email}:\n  ${link}\n` +
          `  Set RESEND_API_KEY in .env to send real emails.`,
      );
      return;
    }

    const html = `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
        <h2>Password Reset — SejiloChat</h2>
        <p>Click the button below to reset your password:</p>
        <a href="${link}" style="display:inline-block;padding:12px 24px;background:#6C47FF;color:#fff;text-decoration:none;border-radius:6px;font-weight:bold">
          Reset Password
        </a>
        <p style="color:#666;font-size:13px;margin-top:24px">
          This link expires in 1 hour. If you did not request a reset, ignore this email.
        </p>
      </div>
    `;

    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: this.fromAddress,
          to: [email],
          subject: 'Reset your SejiloChat password',
          html,
        }),
      });

      if (!res.ok) {
        const body = await res.text();
        this.logger.error(`Resend email failed (${res.status}): ${body}`);
      } else {
        this.logger.log(`Password reset email sent to ${email}`);
      }
    } catch (err) {
      this.logger.error(`Failed to send password reset email: ${(err as Error).message}`);
    }
  }
}
