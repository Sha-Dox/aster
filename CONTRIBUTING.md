# Contributing

Use Xcode 26 or newer. Run `swift test` and `scripts/build-app.sh` before submitting a change. Test OAuth from the packaged app with correct bundle metadata. Keep tests isolated with temporary SQLite databases and stub API responses. Never commit credentials, mailbox exports or authentication archives.

Preserve cache-first behavior, readable original mail, durable offline changes, recoverable deletion and explicit user-triggered model actions. Send integration tests require dedicated mailboxes and deliberate recipients.

Priority work includes live Microsoft and Google integration validation, larger-mailbox benchmarks, accessibility testing, inline attachment rendering, send-uncertainty recovery UX, account management and public release verification. See RELEASE_READINESS.md.
