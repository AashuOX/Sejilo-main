import { IsNotEmpty, Matches } from 'class-validator';

export class SendPhoneOtpDto {
  @IsNotEmpty({ message: 'Phone number is required.' })
  @Matches(/^\+[1-9]\d{7,14}$/, {
    message: 'Phone number must be in E.164 format (e.g. +1234567890).',
  })
  phoneNumber: string;
}