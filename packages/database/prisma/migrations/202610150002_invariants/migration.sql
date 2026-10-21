-- Database-enforced ownership references and lifecycle invariants.
ALTER TABLE "User" ADD CONSTRAINT "User_role_check" CHECK (role IN ('ADMIN','ENGINEER'));
ALTER TABLE "Session" ADD CONSTRAINT "Session_audience_check" CHECK (audience IN ('web','mobile'));
ALTER TABLE "SubmissionAttempt" ADD CONSTRAINT "Attempt_status_check" CHECK (status IN ('accepted','cancelled'));
ALTER TABLE "User" ADD CONSTRAINT "User_organization_fk" FOREIGN KEY ("organizationId") REFERENCES "Organization"(id);
CREATE UNIQUE INDEX "User_id_org_key" ON "User"(id,"organizationId");
CREATE UNIQUE INDEX "Type_id_org_key" ON "EngineerType"(id,"organizationId");
CREATE UNIQUE INDEX "Template_id_org_key" ON "Template"(id,"organizationId");
CREATE UNIQUE INDEX "Version_id_org_key" ON "TemplateVersion"(id,"organizationId");
CREATE UNIQUE INDEX "Device_id_owner_key" ON "Device"(id,"userId");
CREATE UNIQUE INDEX "one_active_assignment" ON "EngineerAssignment"("userId") WHERE "validTo" IS NULL;
ALTER TABLE "Session" ADD CONSTRAINT "Session_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id);
ALTER TABLE "EngineerType" ADD CONSTRAINT "Type_organization_fk" FOREIGN KEY ("organizationId") REFERENCES "Organization"(id);
ALTER TABLE "EngineerType" ADD CONSTRAINT "Type_default_template_fk" FOREIGN KEY ("defaultTemplateId") REFERENCES "Template"(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE "EngineerAssignment" ADD CONSTRAINT "Assignment_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id);
ALTER TABLE "EngineerAssignment" ADD CONSTRAINT "Assignment_type_fk" FOREIGN KEY ("typeId") REFERENCES "EngineerType"(id);
ALTER TABLE "Device" ADD CONSTRAINT "Device_owner_org_fk" FOREIGN KEY ("userId","organizationId") REFERENCES "User"(id,"organizationId");
ALTER TABLE "OfflineEntitlement" ADD CONSTRAINT "Entitlement_owner_org_fk" FOREIGN KEY ("userId","organizationId") REFERENCES "User"(id,"organizationId");
ALTER TABLE "OfflineEntitlement" ADD CONSTRAINT "Entitlement_device_owner_fk" FOREIGN KEY ("deviceId","userId") REFERENCES "Device"(id,"userId");
ALTER TABLE "OfflineEntitlement" ADD CONSTRAINT "Entitlement_type_org_fk" FOREIGN KEY ("typeId","organizationId") REFERENCES "EngineerType"(id,"organizationId");
ALTER TABLE "Template" ADD CONSTRAINT "Template_type_org_fk" FOREIGN KEY ("typeId","organizationId") REFERENCES "EngineerType"(id,"organizationId");
ALTER TABLE "Template" ADD CONSTRAINT "Template_published_version_fk" FOREIGN KEY ("currentPublishedVersionId") REFERENCES "TemplateVersion"(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE "TemplateDraft" ADD CONSTRAINT "Draft_template_fk" FOREIGN KEY ("templateId") REFERENCES "Template"(id);
ALTER TABLE "TemplateDraft" ADD CONSTRAINT "Draft_editor_fk" FOREIGN KEY ("updatedBy") REFERENCES "User"(id);
ALTER TABLE "TemplateVersion" ADD CONSTRAINT "Version_template_org_fk" FOREIGN KEY ("templateId","organizationId") REFERENCES "Template"(id,"organizationId");
ALTER TABLE "TemplateVersion" ADD CONSTRAINT "Version_publisher_fk" FOREIGN KEY ("publishedBy") REFERENCES "User"(id);
ALTER TABLE "Report" ADD CONSTRAINT "Report_owner_org_fk" FOREIGN KEY ("userId","organizationId") REFERENCES "User"(id,"organizationId");
ALTER TABLE "Report" ADD CONSTRAINT "Report_type_org_fk" FOREIGN KEY ("typeId","organizationId") REFERENCES "EngineerType"(id,"organizationId");
ALTER TABLE "Report" ADD CONSTRAINT "Report_version_org_fk" FOREIGN KEY ("templateVersionId","organizationId") REFERENCES "TemplateVersion"(id,"organizationId");
ALTER TABLE "Receipt" ADD CONSTRAINT "Receipt_report_fk" FOREIGN KEY ("reportId") REFERENCES "Report"(id);
ALTER TABLE "SubmissionAttempt" ADD CONSTRAINT "Attempt_owner_org_fk" FOREIGN KEY ("userId","organizationId") REFERENCES "User"(id,"organizationId");
ALTER TABLE "SubmissionAttempt" ADD CONSTRAINT "Attempt_receipt_fk" FOREIGN KEY ("receiptId") REFERENCES "Receipt"(id);
CREATE FUNCTION protect_published_schema() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (NEW."templateId",NEW."versionNumber",NEW.schema,NEW."canonicalSchema",NEW."schemaHash",NEW."organizationId",NEW."publishedBy",NEW."publishedAt")
 IS DISTINCT FROM (OLD."templateId",OLD."versionNumber",OLD.schema,OLD."canonicalSchema",OLD."schemaHash",OLD."organizationId",OLD."publishedBy",OLD."publishedAt") THEN
   RAISE EXCEPTION 'Published schema is immutable';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER immutable_published_schema BEFORE UPDATE ON "TemplateVersion" FOR EACH ROW EXECUTE FUNCTION protect_published_schema();
