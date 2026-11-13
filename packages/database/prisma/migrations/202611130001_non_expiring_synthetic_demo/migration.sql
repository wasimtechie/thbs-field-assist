-- Existing account leases retain their expiry. Only explicitly authorised
-- synthetic demo provisioning can create a lease without an expiry.
ALTER TABLE "OfflineEntitlement" ALTER COLUMN "expiresAt" DROP NOT NULL;
