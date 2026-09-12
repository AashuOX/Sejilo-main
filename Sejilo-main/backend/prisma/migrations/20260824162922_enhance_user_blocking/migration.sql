-- AlterTable Block to add muting and reporting
ALTER TABLE "blocks" ADD COLUMN "is_muted" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "blocks" ADD COLUMN "report_reason" VARCHAR(255);
ALTER TABLE "blocks" ADD COLUMN "report_details" TEXT;

-- CreateIndex for efficient muting queries
CREATE INDEX "idx_blocks_muted" ON "blocks"("blocked_id") WHERE "is_muted" = true;
CREATE INDEX "idx_blocks_blocker_muted" ON "blocks"("blocker_id", "is_muted");
