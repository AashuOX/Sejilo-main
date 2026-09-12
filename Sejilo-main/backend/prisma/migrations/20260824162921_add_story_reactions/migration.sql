-- CreateTable StoryReaction
CREATE TABLE "story_reactions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "story_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "emoji" VARCHAR(10) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "story_reactions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "story_reactions_story_id_user_id_emoji_key" ON "story_reactions"("story_id", "user_id", "emoji");

-- CreateIndex
CREATE INDEX "story_reactions_story_id_idx" ON "story_reactions"("story_id");

-- CreateIndex
CREATE INDEX "story_reactions_user_id_idx" ON "story_reactions"("user_id");

-- AddForeignKey
ALTER TABLE "story_reactions" ADD CONSTRAINT "story_reactions_story_id_fkey" FOREIGN KEY ("story_id") REFERENCES "stories"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "story_reactions" ADD CONSTRAINT "story_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
