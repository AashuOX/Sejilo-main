-- Enable trigram similarity search for GIN fuzzy-search indexes below
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- CreateTable
CREATE TABLE "device_keys" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "device_id" UUID NOT NULL,
    "key_type" TEXT NOT NULL DEFAULT 'x25519',
    "public_key" BYTEA NOT NULL,
    "signature" BYTEA NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "device_keys_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "device_keys_user_id_idx" ON "device_keys"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "device_keys_device_id_key" ON "device_keys"("device_id");

-- CreateIndex
CREATE INDEX "conversations_last_message_at_idx" ON "conversations"("last_message_at" DESC);

-- CreateIndex
CREATE INDEX "messages_conversation_id_id_idx" ON "messages"("conversation_id", "id" DESC);

-- CreateIndex
CREATE INDEX "messages_text_gin" ON "messages" USING GIN ("text" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "posts_caption_gin" ON "posts" USING GIN ("caption" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "profiles_username_gin" ON "profiles" USING GIN ("username" gin_trgm_ops);

-- CreateIndex
CREATE INDEX "profiles_display_name_gin" ON "profiles" USING GIN ("display_name" gin_trgm_ops);

-- AddForeignKey
ALTER TABLE "device_keys" ADD CONSTRAINT "device_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "device_keys" ADD CONSTRAINT "device_keys_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE CASCADE;
