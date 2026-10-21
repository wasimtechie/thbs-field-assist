# THBS demo accounts and access management

Updated workflow: [Clients, squads and messaging](client-team-messaging.md) adds Team Lead and Sales roles, primary-squad assignment, limited engineer dashboard access and messaging for all active roles. The older account-only verification below remains historical; use the linked role matrix for the current scope.

The local dashboard now provides **Field engineers** (`/engineers`) and **IT employees** (`/employees`). Administrators can create profiles and credentials, edit details, assign an engineer type or dashboard role, reset a password, pause/reactivate, remove and restore accounts. Search covers name, email, employee ID and department; status filters and pagination apply on the server.

Profiles include name, email, employee ID, department, designation, phone and base location. Demo names/employee IDs are synthetic. Phone/location are intentionally blank until supplied. Passwords are Argon2 hashes; the system never returns an existing password. New/reset passwords accept six or more characters for this local demonstration.

## Requested credentials

Every account below uses the user-requested password **`123456`**. Emails are case insensitive. Repeated fibre entries and the repeated site-survey address were deduplicated.

| Sign-in | Email | Access / assigned form |
| --- | --- | --- |
| Dashboard | admin@thbs.com | Administrator |
| Dashboard | waseem@thbs.com | Operations Manager |
| Dashboard | test@thbs.com | Viewer |
| Flutter app | fibre1@thbs.com | Fibre installation |
| Flutter app | fibre2@thbs.com | Fibre installation |
| Flutter app | repair1@thbs.com | Fault repair |
| Flutter app | repair2@thbs.com | Fault repair |
| Flutter app | business1@thbs.com | Business |
| Flutter app | business2@thbs.com | Business |
| Flutter app | site-survey@thbs.com | Site survey |

Waseem/test retain their existing user IDs and report history. Their open field jobs were transferred to fibre1/fibre2 when they became dashboard employees; their old sessions were revoked. Existing legacy demo accounts remain available. Normal `db:seed` creates missing THBS demo accounts but preserves existing credentials, roles and profile edits. The explicit local-only `scripts/provision-thbs-accounts.ts` resets the requested catalog; it must not be rerun casually because it revokes their sessions. It refuses production mode.

## Access levels

| Capability | Administrator | Operations Manager | Template Manager | Viewer |
| --- | --- | --- | --- | --- |
| Workspace summary | Yes | Yes | Yes, report records omitted | Yes |
| Jobs, reports, review inbox, asset history | Read/write | Read/write, including review | No | Read only |
| Forms and engineer types | Manage | Read type catalog only | Manage | No |
| Engineer directory and device readiness | Read | Read | Read | No |
| Accounts, credentials and employee roles | Manage | No | No | No |

Field Engineer can use the app and a dashboard limited to its own jobs, linked clients, reports and asset visits. IT accounts cannot log into the mobile audience. All active roles can message organisation colleagues; private chats require participation. Unauthorized navigation shows an access-restricted page. The API independently enforces each permission; hiding controls is supplementary.

Account mutation uses `expectedRevision` to prevent stale changes, workspace scoping, unique normalized email and employee ID checks, and active-type validation. Users cannot pause/remove themselves or change their own role. Serializable transactions preserve at least one active administrator even during concurrent demotions. Changing an engineer into an employee requires first resolving/reassigning open jobs. Changes are audited without passwords.

**Remove** revokes access and retains the account, report receipts, assignments and history. Use the Removed filter and Manage → Restore account to restore it. This is recoverable removal, not a database purge. Pause is reversible and keeps the account in the current directory. Email/password/role changes and pause/removal revoke existing online sessions. A phone already offline cannot receive an immediate revocation: its prior signed entitlement remains bounded by the existing offline lease (up to 72 hours), and online requests are blocked when it reconnects. Expiry does not delete encrypted work.

## Demo path

1. Sign in with admin@thbs.com. Open IT employees → Access levels to explain the four dashboard roles.
2. Open Add IT employee or Add field engineer, enter the profile and initial password, and choose a dashboard access level or engineer type.
3. Manage an account to update details/password, pause/reactivate, or remove/restore. Self-access controls are deliberately protected.
4. Sign in as waseem@thbs.com to assign work/review reports; sign in as test@thbs.com to show read-only views.
5. Use one of the seven field accounts in the existing Flutter build. Online initial login/provisioning still needs a reachable backend. The current APK's laptop-loopback endpoint cannot support an independent remote phone login without endpoint configuration.

## Verification

- Shared contracts: **69 tests pass**, including seven account/RBAC tests (`evidence/accounts-shared-tests.log`).
- Real local API/PostgreSQL verification: **93 checks pass**, covering all 10 requested logins, seven correct type mappings, audience restrictions, role permissions, directory search, duplicate email/code, profile updates, stale revisions, password reset/session revocation, pause/reactivation, removal/restoration, self-access protection, cross-workspace boundaries, concurrent administrator demotions, mobile ownership and signed provisioning (`evidence/accounts-api-checks.json`, script `scripts/check-accounts.ts`). Lifecycle fixtures are clearly marked synthetic and removed through the recovery flow after checks. An isolated fixture workspace is cleaned up separately.
- Final TypeScript and production build evidence: `evidence/accounts-typecheck.log`, `evidence/accounts-admin-build.log`.
- Browser evidence: account lists, profile dialog, Viewer restrictions and responsive layout in `evidence/accounts-*.png`.

The account-only change did not require a Flutter update. The later client/team/messaging workflow ships in build 2009 with connection settings and encrypted action queues. This verification does not certify physical Android/iPhone permissions, camera/GPS, speech accuracy or airplane-mode behavior.
