-- CreateTable UserRecommendation
CREATE TABLE "user_recommendations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "recommended_user_id" UUID NOT NULL,
    "score" DOUBLE PRECISION NOT NULL,
    "reason_tags" TEXT[],
    "computed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_recommendations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_recommendations_user_id_recommended_user_id_key" ON "user_recommendations"("user_id", "recommended_user_id");

-- CreateIndex
CREATE INDEX "user_recommendations_user_id_score_idx" ON "user_recommendations"("user_id", "score" DESC);

-- AddForeignKey
ALTER TABLE "user_recommendations" ADD CONSTRAINT "user_recommendations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_recommendations" ADD CONSTRAINT "user_recommendations_recommended_user_id_fkey" FOREIGN KEY ("recommended_user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable RecommendationDismissal
CREATE TABLE "recommendation_dismissals" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "recommended_user_id" UUID NOT NULL,
    "dismissed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "recommendation_dismissals_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "recommendation_dismissals_user_id_recommended_user_id_key" ON "recommendation_dismissals"("user_id", "recommended_user_id");

-- CreateIndex
CREATE INDEX "recommendation_dismissals_user_id_idx" ON "recommendation_dismissals"("user_id");

-- AddForeignKey
ALTER TABLE "recommendation_dismissals" ADD CONSTRAINT "recommendation_dismissals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "recommendation_dismissals" ADD CONSTRAINT "recommendation_dismissals_recommended_user_id_fkey" FOREIGN KEY ("recommended_user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;