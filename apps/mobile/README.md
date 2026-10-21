# field_assist

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Clients, squads and communication

The updated app includes engineer acceptance/decline with reason, squad/lead contact shortcuts, organisation fuzzy search, private and team chats, unread alerts and a SQLCipher outbox for messages/responses. New briefs retain an assignment generation in frozen reports. Responses send before dependent report uploads. The normal build supports a server-address setting on sign-in; a private local Wi-Fi endpoint is accepted only in the explicitly enabled demo build. Alerts refresh while the app is open/unlocked; closed-app push is not configured. See `../../docs/design/client-team-messaging.md` for accounts, rehearsal, exact offline behavior and verification limits.
