CREATE TABLE "WorkOrder" (
  "id" UUID PRIMARY KEY,
  "organizationId" UUID NOT NULL REFERENCES "Organization"("id"),
  "title" TEXT NOT NULL,
  "site" TEXT NOT NULL,
  "instructions" TEXT NOT NULL DEFAULT '',
  "assetReference" TEXT NOT NULL DEFAULT '',
  "assigneeId" UUID NOT NULL REFERENCES "User"("id"),
  "typeId" UUID NOT NULL REFERENCES "EngineerType"("id"),
  "priority" TEXT NOT NULL DEFAULT 'normal' CHECK ("priority" IN ('normal','high','urgent')),
  "status" TEXT NOT NULL DEFAULT 'assigned' CHECK ("status" IN ('assigned','submitted','completed','follow_up')),
  "dueAt" TIMESTAMP(3) NOT NULL,
  "latestReportId" UUID REFERENCES "Report"("id"),
  "reviewNote" TEXT NOT NULL DEFAULT '',
  "createdBy" UUID NOT NULL REFERENCES "User"("id"),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  "revision" INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX "WorkOrder_organizationId_status_dueAt_id_idx" ON "WorkOrder"("organizationId","status","dueAt","id");
CREATE INDEX "WorkOrder_assigneeId_updatedAt_id_idx" ON "WorkOrder"("assigneeId","updatedAt","id");
CREATE INDEX "WorkOrder_organizationId_assetReference_idx" ON "WorkOrder"("organizationId","assetReference");
ALTER TABLE "Report" ADD COLUMN "workOrderId" UUID REFERENCES "WorkOrder"("id");
CREATE INDEX "Report_workOrderId_idx" ON "Report"("workOrderId");
CREATE TABLE "ReportReview" (
  "reportId" UUID PRIMARY KEY REFERENCES "Report"("id"),
  "organizationId" UUID NOT NULL REFERENCES "Organization"("id"),
  "decision" TEXT NOT NULL CHECK ("decision" IN ('approved','follow_up')),
  "note" TEXT NOT NULL DEFAULT '',
  "reviewerId" UUID NOT NULL REFERENCES "User"("id"),
  "reviewedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK ("decision" != 'follow_up' OR length(trim("note")) > 0)
);
CREATE INDEX "ReportReview_organizationId_reviewedAt_idx" ON "ReportReview"("organizationId","reviewedAt");
-- Decisions are append-only. A follow-up is a new report; original evidence stays intact.
CREATE FUNCTION protect_report_review() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'Report reviews are immutable'; END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "ReportReview_immutable" BEFORE UPDATE OR DELETE ON "ReportReview"
FOR EACH ROW EXECUTE FUNCTION protect_report_review();
