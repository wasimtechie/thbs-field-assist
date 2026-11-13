CREATE TABLE "CustomerJobStatus" (
  "workOrderId" UUID NOT NULL PRIMARY KEY REFERENCES "WorkOrder"("id") ON DELETE CASCADE,
  "organizationId" UUID NOT NULL REFERENCES "Organization"("id"),
  "customerEmail" TEXT NOT NULL,
  "appointmentStartAt" TIMESTAMP(3), "appointmentEndAt" TIMESTAMP(3),
  "appointmentTimezone" TEXT NOT NULL DEFAULT 'Europe/London',
  "activationStatus" TEXT NOT NULL DEFAULT 'not_confirmed',
  "activationAt" TIMESTAMP(3), "activationNote" TEXT NOT NULL DEFAULT '',
  "revision" INTEGER NOT NULL DEFAULT 1, "updatedBy" UUID NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CustomerJobStatus_activation" CHECK ("activationStatus" IN ('not_confirmed','scheduled','active','blocked'))
);
CREATE INDEX "CustomerJobStatus_organizationId_customerEmail_idx" ON "CustomerJobStatus"("organizationId", "customerEmail");
CREATE TABLE "ChatmConnectionKey" (
  "id" UUID NOT NULL PRIMARY KEY, "organizationId" UUID NOT NULL REFERENCES "Organization"("id"),
  "label" TEXT NOT NULL, "tokenHash" TEXT NOT NULL, "revokedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX "ChatmConnectionKey_tokenHash_key" ON "ChatmConnectionKey"("tokenHash");
CREATE INDEX "ChatmConnectionKey_organizationId_idx" ON "ChatmConnectionKey"("organizationId");
