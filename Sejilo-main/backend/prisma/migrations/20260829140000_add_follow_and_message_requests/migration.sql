-- Schema drift repair.
--
-- `FollowRequest` and `MessageRequest` were added to schema.prisma without a
-- migration, so the generated client queried tables Postgres did not have.
-- Every follow went through `followRequest.findUnique` and came back as a 500
-- (Prisma P2021, "table public.follow_requests does not exist"), which meant
-- the follow button was broken for every account, private or not.

-- CreateTable FollowRequest
CREATE TABLE "follow_requests" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "requester_id" UUID NOT NULL,
    "target_id" UUID NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "follow_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
-- One pending row per pair: `follow()` upserts on this pair, and without the
-- unique index a user could stack duplicate requests by tapping twice.
CREATE UNIQUE INDEX "follow_requests_requester_id_target_id_key" ON "follow_requests"("requester_id", "target_id");

-- CreateIndex
CREATE INDEX "follow_requests_target_id_idx" ON "follow_requests"("target_id");

-- CreateIndex
CREATE INDEX "follow_requests_status_idx" ON "follow_requests"("status");

-- AddForeignKey
ALTER TABLE "follow_requests" ADD CONSTRAINT "follow_requests_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "follow_requests" ADD CONSTRAINT "follow_requests_target_id_fkey" FOREIGN KEY ("target_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable MessageRequest
CREATE TABLE "message_requests" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "sender_id" UUID NOT NULL,
    "recipient_id" UUID NOT NULL,
    "text" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "message_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "message_requests_recipient_id_idx" ON "message_requests"("recipient_id");

-- CreateIndex
CREATE INDEX "message_requests_status_idx" ON "message_requests"("status");

-- AddForeignKey
ALTER TABLE "message_requests" ADD CONSTRAINT "message_requests_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "message_requests" ADD CONSTRAINT "message_requests_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateIndex
-- `hiddenAuthorIds` reads blocks from either side, so the reverse direction is
-- looked up as often as the forward one; only blocker_id was indexed.
CREATE INDEX IF NOT EXISTS "blocks_blocked_id_idx" ON "blocks"("blocked_id");

-- AlterTable
-- Declared as String in the schema, so the client will send more than 255
-- characters and Postgres would reject the write.
ALTER TABLE "blocks" ALTER COLUMN "report_reason" SET DATA TYPE TEXT;

-- One reaction per viewer per story.
--
-- `stories.service.ts` upserts on the compound key `storyId_userId`, which the
-- generated client derives from the schema's `@@unique([storyId, userId])`. The
-- database instead carried a three-column unique including `emoji`, so the
-- ON CONFLICT target did not exist and reacting to a story failed. Changing
-- your reaction is meant to replace the old one, not add a second row.
DELETE FROM "story_reactions" older
USING "story_reactions" newer
WHERE older."story_id" = newer."story_id"
  AND older."user_id" = newer."user_id"
  AND (older."created_at" < newer."created_at"
       OR (older."created_at" = newer."created_at" AND older."id" < newer."id"));

DROP INDEX IF EXISTS "story_reactions_story_id_user_id_emoji_key";

CREATE UNIQUE INDEX "story_reactions_story_id_user_id_key" ON "story_reactions"("story_id", "user_id");

-- AlterTable
-- varchar(10) counts characters, and a single ZWJ emoji sequence (a flag, a
-- family, anything with a variation selector) runs past ten of them.
ALTER TABLE "story_reactions" ALTER COLUMN "emoji" SET DATA TYPE TEXT;
