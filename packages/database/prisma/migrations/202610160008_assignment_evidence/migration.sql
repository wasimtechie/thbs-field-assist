ALTER TABLE "Report" ADD COLUMN "workOrderAssignmentRevision" INTEGER;
ALTER TABLE "AssignmentResponse" ADD COLUMN brief JSONB;
CREATE FUNCTION protect_assignment_response() RETURNS trigger AS $$
BEGIN RAISE EXCEPTION 'Assignment responses are immutable'; END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "AssignmentResponse_immutable" BEFORE UPDATE OR DELETE ON "AssignmentResponse"
FOR EACH ROW EXECUTE FUNCTION protect_assignment_response();
