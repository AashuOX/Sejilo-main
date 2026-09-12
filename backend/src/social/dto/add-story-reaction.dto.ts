import { IsString, IsNotEmpty, Matches } from 'class-validator';

export class AddStoryReactionDto {
  @IsString()
  @IsNotEmpty()
  @Matches(/^[\p{Emoji}]+$/u, {
    message: 'emoji must be a valid emoji character',
  })
  emoji: string;
}