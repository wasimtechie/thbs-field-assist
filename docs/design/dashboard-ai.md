# Dashboard AI

Three on-demand features are available in the existing THBS colour scheme:

| Where | What it does | Operator action |
| --- | --- | --- |
| AI assistant; Overview; Work orders → Ask AI | Priorities, pending responses, blockers and editable handover drafts, linked to source jobs | Choose a quick prompt or ask a question |
| Clients → AI client brief | Summarizes jobs for that permitted client | Open the client-scoped assistant |
| Submissions → a report → AI evidence review | Summarizes original recorded answers, identifies evidence gaps and suggests a follow-up | Review with AI; optionally insert the draft into the review note |
| Work orders → Assign job / Edit | Drafts visit instructions using the title, existing instructions and the selected engineer's published capture form | Choose engineer, enter title, Draft with AI, inspect, then Use draft |

AI does not save assignments, approve reports, change field evidence or send messages. Use draft replaces the current instructions or review-note text locally; the normal save/review action remains required. Review decisions and received reports retain their existing immutable history. A report receipt still means delivery, not supervisor approval.

## Running locally

The current development server has an authorized key in memory. No key is saved in the repository, browser code, mobile configuration, APK, logs or screenshots. When restarting, use `python3 scripts/dev-with-ai.py`; it prompts without echoing the key, tests a tiny synthetic request, and starts Next.js. Stop any existing port-3000 server first. An ordinary server without a key shows AI setup needed, while normal workspace functionality remains available.

Production should supply `OPENAI_API_KEY` through its server secret environment. `OPENAI_MODEL` optionally overrides the pinned default `gpt-4.1-mini-2025-04-14`. No credentials belong in `NEXT_PUBLIC_` variables. Rotate any key pasted into chat; enter the replacement at the next server start.

The server uses the [Responses API with strict structured output](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses), no tools and a 45-second timeout. Requests set `store:false`. This request setting is not a claim of zero retention: provider abuse-monitoring and organisation data controls follow [OpenAI's data policy](https://developers.openai.com/api/docs/guides/your-data).

## Data and permissions

The API scopes source queries before generation. Admin and Operations see permitted organisation work; Team Leads see led squads; Engineers see their own work; Sales sees permitted client-linked jobs and can draft assignments but cannot request report evidence. Viewers can read AI summaries and permitted report analysis, but cannot draft assignments. Template Managers and mobile bearer sessions cannot invoke these dashboard endpoints. Sources and permissions are checked again before returning an answer.

Operations uses full filtered status/response counts and at most the earliest-due 40 open jobs. A selected client/board narrows the existing permission scope. Report review uses visible answers and validation results from the report's original published form. Brief writing uses the engineer's current published form, including conditional-question indicators.

The AI context excludes account records, colleague profiles, private chats, attendance, precise GPS metadata and dedicated site/contact address fields. Selected free-text job/form/report content is sent to OpenAI. Obvious email addresses and credential patterns are redacted; this is not a complete sensitive-data detector. Check free text before requesting AI. Images/audio are not sent. The assistant receives text only and cannot verify physical work or image evidence.

All source text is treated as untrusted. The model has no write tools. Responses are validated against a schema and allowed source IDs; links are constructed by the server. Text is rendered as plain React content. These controls do not establish factual accuracy: operators must check the cited records.

## Cost, concurrency and failure behaviour

- Maximum six new provider attempts per user per five minutes, and 100 per organisation per UTC day; enforced through serializable database reservations.
- Matching answers are reused for five minutes, keyed to user, role, inputs, current context, model and prompt version. No cache sharing between users.
- A 70-second generation lease prevents duplicate parallel calls for the same context. Failure has a one-minute retry cooldown.
- A changed underlying context, revoked session or changed access prevents stale delivery. No stale answer is substituted when generation fails.
- OpenAI authentication, quota, rate, refusal, malformed-output and timeout errors have readable messages. Provider authentication errors do not log the dashboard user out.
- Audit entries retain request kind, context hash, model and token usage; they do not log raw prompts or the key. Validated AI output is cached in PostgreSQL, scoped to the original user. Expiry controls reuse, not physical deletion of cache/audit rows.

## Verification

`npm test` covers provider requests, error sanitization, contracts and AI permissions. `npx tsx scripts/check-ai.ts --live` verifies local PostgreSQL permissions, caching, limits and all three real OpenAI endpoints using a separate synthetic organisation. Without `--live`, it uses an injected test provider and does not send external requests. Test accounts are disabled and sessions revoked on completion unless explicitly keeping the browser fixture for local visual QA.

Evidence is in `docs/evidence/ai-connection.json`, `ai-checks.json`, `ai-live.json`, `ai-unit-tests.log`, `ai-typecheck.log` and the AI browser screenshots. Live output is evidence of those synthetic requests, not a guarantee of future provider uptime or billing availability. Cloud AI needs internet; the Flutter offline capture, local voice models, frozen outbox and reconnect synchronization are unchanged. The dashboard-only update does not require a new APK.
