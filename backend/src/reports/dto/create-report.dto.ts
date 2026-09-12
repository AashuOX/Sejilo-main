import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * Body for the two report endpoints.
 *
 * `reason` stays free text rather than an enum: the app sends the human label a
 * person tapped ("Inappropriate content", "Spam"), and pinning the server to a
 * fixed list would start rejecting reports the moment the client's sheet gains a
 * row. The length caps are what keep it a label and not an essay.
 */
export class CreateReportDto {
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  reason!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  details?: string;
}
