ALTER TABLE "User" ADD COLUMN "removedAt" TIMESTAMP(3),
  ADD COLUMN "employeeCode" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "department" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "jobTitle" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "phone" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "baseLocation" TEXT NOT NULL DEFAULT '';
CREATE UNIQUE INDEX "User_employee_code_per_org" ON "User"("organizationId","employeeCode") WHERE "employeeCode" <> '';
