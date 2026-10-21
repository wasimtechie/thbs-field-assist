CREATE TABLE "AiGeneration" (id UUID PRIMARY KEY,"organizationId" UUID NOT NULL,"userId" UUID NOT NULL,kind TEXT NOT NULL,"cacheKey" TEXT NOT NULL,"sourceHash" TEXT NOT NULL,model TEXT NOT NULL,status TEXT NOT NULL,"leaseId" UUID NOT NULL,result JSONB,usage JSONB,"expiresAt" TIMESTAMP(3) NOT NULL,"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,"updatedAt" TIMESTAMP(3) NOT NULL);
CREATE UNIQUE INDEX "AiGeneration_cacheKey_key" ON "AiGeneration"("cacheKey");
CREATE INDEX "AiGeneration_organizationId_userId_createdAt_idx" ON "AiGeneration"("organizationId","userId","createdAt");
CREATE TABLE "AiRequest" (id UUID PRIMARY KEY,"organizationId" UUID NOT NULL,"userId" UUID NOT NULL,"generationId" UUID NOT NULL,status TEXT NOT NULL,"errorCode" TEXT,"createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX "AiRequest_organizationId_createdAt_idx" ON "AiRequest"("organizationId","createdAt");
CREATE INDEX "AiRequest_userId_createdAt_idx" ON "AiRequest"("userId","createdAt");
ALTER TABLE "AiRequest" ADD CONSTRAINT "AiRequest_generationId_fkey" FOREIGN KEY ("generationId") REFERENCES "AiGeneration"(id);
