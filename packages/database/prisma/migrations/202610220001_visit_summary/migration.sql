CREATE TABLE "VisitSummary" (
  "id" UUID NOT NULL,
  "organizationId" UUID NOT NULL,
  "clientSummaryId" UUID NOT NULL,
  "clientReportId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "workOrderId" UUID,
  "teamId" UUID,
  "values" JSONB NOT NULL,
  "sources" JSONB NOT NULL,
  "payloadHash" TEXT NOT NULL,
  "confirmedAt" TIMESTAMP(3) NOT NULL,
  "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "VisitSummary_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "VisitSummary_organizationId_clientSummaryId_key" ON "VisitSummary"("organizationId", "clientSummaryId");
CREATE INDEX "VisitSummary_organizationId_receivedAt_id_idx" ON "VisitSummary"("organizationId", "receivedAt", "id");
