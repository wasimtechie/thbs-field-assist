# Ask Chatm about Field Assist jobs

Customer website: http://localhost:3000/demo

Chatm connection setup: http://localhost:3000/dashboard/integrations/backend

Job details: http://localhost:3002/work-orders

Submitted engineer forms: http://localhost:3002/submissions?view=visits

The local S1 synthetic job is linked to `customer@fieldassist.demo`. In Work orders, open S1 and use **Customer updates for Chatm** to maintain its confirmed appointment and provider activation details. Existing job due dates and passing service tests are never used as a substitute for those confirmations.

The customer verifies the linked email in the Chatm widget, then asks naturally:

- When will the field engineer visit my site?
- The engineer has visited. Is any work remaining?
- When will my Wi-Fi start working?

The bot reads fresh submitted data for that customer. Engineer form submission must finish syncing before it can appear. A confirmed visit summary is separate from operational job completion and provider activation. Unknown dates remain unconfirmed. This Mac uses the explicitly enabled synthetic OTP mode; no email is delivered externally.

For this Mac's interactive demo, expand **Verify email for orders or engineer visits** in the website widget. Use `customer@fieldassist.demo`, enter sample OTP **1234**, then choose **Verify email**. No email link or backend key is needed. The fixed code unlocks only this synthetic Field Assist customer and is disabled outside the configured local demo and in production. Normal customer verification remains separate.

Setup and recovery are documented in Chatm's `docs/FIELD-ASSIST.md`. Field Assist's separate read-only connection credential is stored hashed in `ChatmConnectionKey`, with its original key privately in ignored mode-0600 `.local/chatm-field-assist-connection.json` and encrypted in Chatm's Nango connection service. Revoke by setting the matching key's `revokedAt`; it cannot authenticate to normal dashboard/mobile APIs. Do not paste the credential into a conversation, model prompt or knowledge source.

Local verification: `node --import tsx scripts/check-chatm-customer-jobs.ts` checks the live Field Assist API with isolated synthetic records. `node --import tsx scripts/prepare-chatm-connection.ts` prepares the existing synthetic S1 link and local connection without altering its submissions or inventing appointment/activation dates.

Verified on 23 October 2026: eight Field Assist contract tests, 27 Chatm connector/order/integration tests, both builds, workspace type checks and Chatm lint. Actual model conversations checked all three customer questions with a fresh tool audit for each, correct UK daylight-saving time, unverified/wrong-customer/email-override/workspace rejection, and no invented activation time. The website browser check exercised send-link, emulator helper, sign-in, server verification and forgetting identity. Dashboard job/editor and saved connection views passed browser checks. Temporary synthetic jobs were removed; original S1 and submissions were preserved. No physical microphone or production email/provider integration is claimed.

The subsequent sample-OTP update passed 33 Chatm tests, type checks, lint and a production build. Actual browser checks confirmed that the local widget shows OTP instead of link controls, rejects 9999, accepts 1234 and can clear the identity. The real OTP-authorized chat fetched fresh S1 data through Nango/Field Assist. Wrong emails were rejected and the saved demo identity could not authorize ordinary private integrations.
