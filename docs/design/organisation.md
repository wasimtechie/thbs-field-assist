# Profiles and organisation directory

All signed-in dashboard roles can explore [Organisation](http://localhost:3000/organisation), browse the [People directory](http://localhost:3000/people), and open another active colleague’s profile. The existing purple/teal theme and avatar catalogue remain.

## Walkthrough

1. Open **Account settings → Edit your profile** or [Your profile](http://localhost:3000/profile). Edit **Full name** and select **Save name**. Avatar selection has its own explicit save; it does not submit a pending name edit.
2. Open **Organisation** in the sidebar. Each squad shows its department, responsible lead and a preview of up to four other active members. Click a person to open their profile; **View squad people** lists all matching members with pagination. The overview displays up to 200 squads and tells the user when it is limited.
3. Open a colleague’s **Organisation** view to see their primary squad’s lead, the squads they lead, people in those squads and colleagues they work with. Every person card links to the corresponding profile. **About** shows work email, department, job title, employee ID, work location and primary squad. **Message** opens the existing direct conversation without sending a message automatically.
4. Filter by department, or use the existing fuzzy name/email/employee ID/squad search in the directory. The organisation page also searches squad/lead names and links to the selected department’s people, including departments without a delivery squad.
5. Profile links also appear on team members/leads, account directory names and chat participants. The signed-in user can navigate from their own colleague profile back to profile editing.

Example: [Fibre Engineer 1](http://localhost:3000/people/75aac8b7-1a82-4084-bd3a-5cd0035a003f) shows the Fibre Delivery lead and Fibre Engineer 2. Open that lead to see Fibre Delivery and Site Planning with the three assigned field engineers.

## Relationship and access rules

The hierarchy reflects **primary squad membership → responsible team lead**. It does not infer managers from access roles. An administrator sets primary squad membership in **Field engineers / IT employees → Manage**, and sets each lead in **Teams & squads**. A lead can oversee several squads. A person who leads their own squad is never shown as reporting to themselves. People without an active primary squad are visible through the unassigned directory filter. A paused/removed lead is omitted from public colleague details, and an unavailable-lead message appears until the squad is updated.

Directory visibility is organisation-wide for every supported role, including Field Engineer, Sales, Viewer and Template Manager. It does not broaden operational access. Existing team/job/report/time/client scopes and participant-only conversations remain. Paused/removed people and archived squads are excluded from active colleague relationships. Unknown or foreign colleague IDs return the same unavailable response. Dedicated directory responses select professional profile/team fields explicitly; they omit passwords, personal phone fields, session data, account revisions/permissions, client counts, reports, attendance and private messages.

Self-service profile PATCH accepts only name/avatar, with an optional revision for compatible existing avatar-only clients. Name changes require the current revision. Names are trimmed and limited to 1–100 characters; stale or concurrent conflicting edits return 409. Writes target the authenticated account and cannot change email, department, squad or role. The audit event records changed field names. New names appear on current directory/profile records; original frozen reports and historical evidence remain intact.

## Verification

- 96 shared unit tests pass, including profile input validation and legacy avatar compatibility.
- 83 real local HTTP/PostgreSQL checks cover all seven roles, cross-organisation isolation, safe field selection, department/squad filtering, fuzzy search, pagination, archived/paused/removed handling, name persistence/search, stale/concurrent edits, self-only writes and legacy mobile avatar updates. Tests use isolated synthetic organisations; their accounts are disabled and sessions revoked afterwards.
- TypeScript and the final production dashboard build pass.
- Browser checks at 1440px and 390px cover the organisation overview, employee/lead profiles, About view, department navigation, typo search and self-name form. No document overflow was observed. The real administrator name was typed into a temporary preview and restored without saving; persistence is verified using synthetic API accounts. No messages were sent.

Evidence: `docs/evidence/organisation-*`. This is a dashboard/backend update; no Flutter source or APK was changed, and APK generation still requires an explicit user request.
