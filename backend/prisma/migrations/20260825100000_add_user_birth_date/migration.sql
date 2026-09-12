-- Birthday is private account-safety data and is never exposed in profiles.
ALTER TABLE "users" ADD COLUMN "birth_date" DATE;
