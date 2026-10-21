-- Nullable so historical reports and existing frozen offline queues remain valid.
ALTER TABLE "Report" ADD COLUMN "location" JSONB;
