CREATE EXTENSION IF NOT EXISTS pg_trgm;
ALTER TABLE "User" DROP CONSTRAINT "User_role_check";
ALTER TABLE "User" ADD CONSTRAINT "User_role_check" CHECK (role IN ('ADMIN','OPERATIONS_MANAGER','TEAM_LEAD','SALES','TEMPLATE_MANAGER','VIEWER','ENGINEER'));
-- Composite workspace keys prevent accidental cross-organisation associations.
CREATE TABLE "Team" (
 id UUID PRIMARY KEY, "organizationId" UUID NOT NULL REFERENCES "Organization"(id), name TEXT NOT NULL, department TEXT NOT NULL,
 description TEXT NOT NULL DEFAULT '', "leadId" UUID NOT NULL, "archivedAt" TIMESTAMP(3), revision INTEGER NOT NULL DEFAULT 1,
 "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(id,"organizationId"),
 FOREIGN KEY("leadId","organizationId") REFERENCES "User"(id,"organizationId")
);
CREATE INDEX "Team_organizationId_leadId_idx" ON "Team"("organizationId","leadId");
ALTER TABLE "User" ADD COLUMN "teamId" UUID;
ALTER TABLE "User" ADD CONSTRAINT "User_team_org_fk" FOREIGN KEY("teamId","organizationId") REFERENCES "Team"(id,"organizationId");
CREATE INDEX "User_teamId_idx" ON "User"("teamId");
CREATE TABLE "Client" (
 id UUID PRIMARY KEY, "organizationId" UUID NOT NULL REFERENCES "Organization"(id), name TEXT NOT NULL,
 "contactName" TEXT NOT NULL DEFAULT '', email TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
 "teamId" UUID, status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('prospect','active','paused')), "createdBy" UUID NOT NULL,
 revision INTEGER NOT NULL DEFAULT 1,"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"updatedAt" TIMESTAMP(3) NOT NULL,
 UNIQUE(id,"organizationId"), FOREIGN KEY("teamId","organizationId") REFERENCES "Team"(id,"organizationId"),
 FOREIGN KEY("createdBy","organizationId") REFERENCES "User"(id,"organizationId")
);
CREATE INDEX "Client_organizationId_teamId_createdAt_idx" ON "Client"("organizationId","teamId","createdAt");
ALTER TABLE "WorkOrder" ADD COLUMN "teamId" UUID, ADD COLUMN "clientId" UUID,
 ADD COLUMN "assignmentRevision" INTEGER NOT NULL DEFAULT 1, ADD COLUMN "responseStatus" TEXT NOT NULL DEFAULT 'pending' CHECK("responseStatus" IN ('pending','accepted','declined')),
 ADD COLUMN "responseNote" TEXT NOT NULL DEFAULT '', ADD COLUMN "respondedAt" TIMESTAMP(3);
-- Existing jobs predate acceptance; preserve their ability to finish and sync.
UPDATE "WorkOrder" SET "responseStatus"='accepted';
ALTER TABLE "WorkOrder" ADD CONSTRAINT "WorkOrder_team_org_fk" FOREIGN KEY("teamId","organizationId") REFERENCES "Team"(id,"organizationId"),
 ADD CONSTRAINT "WorkOrder_client_org_fk" FOREIGN KEY("clientId","organizationId") REFERENCES "Client"(id,"organizationId");
CREATE INDEX "WorkOrder_team_response_idx" ON "WorkOrder"("organizationId","teamId","responseStatus");
ALTER TABLE "Report" ADD COLUMN "teamId" UUID;
ALTER TABLE "Report" ADD CONSTRAINT "Report_team_org_fk" FOREIGN KEY("teamId","organizationId") REFERENCES "Team"(id,"organizationId");
CREATE TABLE "AssignmentResponse" (
 id UUID PRIMARY KEY,"organizationId" UUID NOT NULL REFERENCES "Organization"(id),"workOrderId" UUID NOT NULL REFERENCES "WorkOrder"(id),"userId" UUID NOT NULL,
 "requestId" UUID NOT NULL,"assignmentRevision" INTEGER NOT NULL,decision TEXT NOT NULL CHECK(decision IN ('accepted','declined')),note TEXT NOT NULL,
 "respondedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,UNIQUE("userId","requestId"),UNIQUE("workOrderId","assignmentRevision"),
 FOREIGN KEY("userId","organizationId") REFERENCES "User"(id,"organizationId"),CHECK(decision!='declined' OR length(trim(note))>0)
);
CREATE TABLE "Conversation" (
 id UUID PRIMARY KEY,"organizationId" UUID NOT NULL REFERENCES "Organization"(id),kind TEXT NOT NULL CHECK(kind IN ('direct','team')),
 "directKey" TEXT,"teamId" UUID UNIQUE,"updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE("organizationId","directKey"), UNIQUE(id,"organizationId"), FOREIGN KEY("teamId","organizationId") REFERENCES "Team"(id,"organizationId"),
 CHECK((kind='direct' AND "directKey" IS NOT NULL AND "teamId" IS NULL) OR (kind='team' AND "teamId" IS NOT NULL AND "directKey" IS NULL))
);
CREATE INDEX "Conversation_organizationId_updatedAt_idx" ON "Conversation"("organizationId","updatedAt");
CREATE TABLE "ConversationMember" (
 "conversationId" UUID NOT NULL REFERENCES "Conversation"(id),"userId" UUID NOT NULL REFERENCES "User"(id),"lastReadSequence" BIGINT NOT NULL DEFAULT 0,
 PRIMARY KEY("conversationId","userId")
);
CREATE INDEX "ConversationMember_userId_idx" ON "ConversationMember"("userId");
CREATE TABLE "Message" (
 id UUID PRIMARY KEY,"organizationId" UUID NOT NULL,"conversationId" UUID NOT NULL,"senderId" UUID NOT NULL,"clientMessageId" UUID NOT NULL,
 sequence BIGSERIAL UNIQUE,text TEXT NOT NULL CHECK(length(trim(text)) BETWEEN 1 AND 4000),"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE("conversationId","senderId","clientMessageId"), FOREIGN KEY("conversationId","organizationId") REFERENCES "Conversation"(id,"organizationId"),
 FOREIGN KEY("senderId","organizationId") REFERENCES "User"(id,"organizationId")
);
CREATE INDEX "Message_conversationId_sequence_idx" ON "Message"("conversationId",sequence);
CREATE TABLE "Notification" (
 id UUID PRIMARY KEY,"organizationId" UUID NOT NULL,"userId" UUID NOT NULL,kind TEXT NOT NULL,"resourceId" UUID NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,
 "deliveryKey" TEXT NOT NULL,"readAt" TIMESTAMP(3),"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE("userId","deliveryKey"), FOREIGN KEY("userId","organizationId") REFERENCES "User"(id,"organizationId")
);
CREATE INDEX "Notification_userId_createdAt_id_idx" ON "Notification"("userId","createdAt",id);
CREATE INDEX "User_directory_fuzzy_idx" ON "User" USING gin (lower(name || ' ' || email || ' ' || department || ' ' || "jobTitle") gin_trgm_ops) WHERE "disabledAt" IS NULL AND "removedAt" IS NULL;
