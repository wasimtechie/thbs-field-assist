-- CreateTable
CREATE TABLE "Organization" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,

    CONSTRAINT "Organization_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "disabledAt" TIMESTAMP(3),
    "revision" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Session" (
    "id" UUID NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "userId" UUID NOT NULL,
    "audience" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "Session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LoginAttempt" (
    "key" TEXT NOT NULL,
    "count" INTEGER NOT NULL,
    "windowStart" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LoginAttempt_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "EngineerType" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "defaultTemplateId" UUID,
    "archivedAt" TIMESTAMP(3),
    "revision" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EngineerType_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EngineerAssignment" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "typeId" UUID NOT NULL,
    "revision" INTEGER NOT NULL,
    "validFrom" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "validTo" TIMESTAMP(3),

    CONSTRAINT "EngineerAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Device" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "platform" TEXT NOT NULL,
    "appVersion" TEXT NOT NULL,
    "osVersion" TEXT NOT NULL,
    "model" TEXT NOT NULL DEFAULT 'Unknown device',
    "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "readiness" JSONB NOT NULL,
    "packageVersion" TEXT,
    "schemaVersion" TEXT,

    CONSTRAINT "Device_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "OfflineEntitlement" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "typeId" UUID NOT NULL,
    "assignmentRevision" INTEGER NOT NULL,
    "allowedTemplates" TEXT[],
    "issuedAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "token" TEXT NOT NULL,

    CONSTRAINT "OfflineEntitlement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Template" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "typeId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "currentPublishedVersionId" UUID,
    "archivedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Template_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TemplateDraft" (
    "templateId" UUID NOT NULL,
    "revision" INTEGER NOT NULL DEFAULT 1,
    "schema" JSONB NOT NULL,
    "updatedBy" UUID NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TemplateDraft_pkey" PRIMARY KEY ("templateId")
);

-- CreateTable
CREATE TABLE "TemplateVersion" (
    "id" UUID NOT NULL,
    "templateId" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "versionNumber" INTEGER NOT NULL,
    "schema" JSONB NOT NULL,
    "canonicalSchema" TEXT NOT NULL,
    "schemaHash" TEXT NOT NULL,
    "publishedBy" UUID NOT NULL,
    "publishedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "disabledAt" TIMESTAMP(3),

    CONSTRAINT "TemplateVersion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SubmissionAttempt" (
    "id" UUID NOT NULL,
    "attemptId" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "clientReportId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "payloadHash" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "receiptId" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SubmissionAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Report" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "clientReportId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "typeId" UUID NOT NULL,
    "templateVersionId" UUID NOT NULL,
    "schemaHash" TEXT NOT NULL,
    "values" JSONB NOT NULL,
    "confirmedAt" TIMESTAMP(3) NOT NULL,
    "originatingTimezone" TEXT NOT NULL,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "demo" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "Report_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Receipt" (
    "id" UUID NOT NULL,
    "reportId" UUID NOT NULL,
    "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Receipt_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" UUID NOT NULL,
    "organizationId" UUID NOT NULL,
    "actorId" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "metadata" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE INDEX "User_organizationId_role_idx" ON "User"("organizationId", "role");

-- CreateIndex
CREATE UNIQUE INDEX "Session_tokenHash_key" ON "Session"("tokenHash");

-- CreateIndex
CREATE INDEX "Session_userId_idx" ON "Session"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "EngineerType_organizationId_slug_key" ON "EngineerType"("organizationId", "slug");

-- CreateIndex
CREATE INDEX "EngineerAssignment_userId_validTo_idx" ON "EngineerAssignment"("userId", "validTo");

-- CreateIndex
CREATE UNIQUE INDEX "EngineerAssignment_userId_revision_key" ON "EngineerAssignment"("userId", "revision");

-- CreateIndex
CREATE INDEX "Device_organizationId_lastSeenAt_id_idx" ON "Device"("organizationId", "lastSeenAt", "id");

-- CreateIndex
CREATE INDEX "OfflineEntitlement_userId_deviceId_idx" ON "OfflineEntitlement"("userId", "deviceId");

-- CreateIndex
CREATE INDEX "Template_organizationId_createdAt_id_idx" ON "Template"("organizationId", "createdAt", "id");

-- CreateIndex
CREATE UNIQUE INDEX "TemplateVersion_templateId_versionNumber_key" ON "TemplateVersion"("templateId", "versionNumber");

-- CreateIndex
CREATE UNIQUE INDEX "SubmissionAttempt_organizationId_userId_attemptId_key" ON "SubmissionAttempt"("organizationId", "userId", "attemptId");

-- CreateIndex
CREATE INDEX "Report_organizationId_receivedAt_id_idx" ON "Report"("organizationId", "receivedAt", "id");

-- CreateIndex
CREATE UNIQUE INDEX "Report_organizationId_clientReportId_key" ON "Report"("organizationId", "clientReportId");

-- CreateIndex
CREATE UNIQUE INDEX "Receipt_reportId_key" ON "Receipt"("reportId");

-- CreateIndex
CREATE INDEX "AuditEvent_organizationId_createdAt_id_idx" ON "AuditEvent"("organizationId", "createdAt", "id");

