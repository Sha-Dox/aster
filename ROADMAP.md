# Roadmap

Priorities are ordered by release readiness. This is a direction, not a delivery commitment.

## Before a production release

- Validate simultaneous Microsoft, Gmail and mixed-provider accounts against dedicated test mailboxes.
- Verify refresh persistence, tenant policies, history/delta recovery, drafts, attachments and deliberate sends.
- Add a clear reconciliation workflow for uncertain sends and remote duplicate drafts.
- Complete light/dark, keyboard, VoiceOver, reduced-transparency and increased-contrast QA.
- Benchmark real large mailboxes and recovery from network loss, quotas and interrupted sync.
- Complete dependency/security review, Google OAuth verification, Developer ID signing and notarization.
- Verify clean installation, upgrades and the supported macOS/hardware matrix.

## Following improvements

- In-app account cache and attachment deletion controls.
- Inline attachment / CID image rendering.
- Bulk mail actions and better mailbox management.
- Push notifications, server-side search and richer search tools.
- Additional providers, including evaluation of IMAP support.

Implementation and validation status live in [RELEASE_READINESS.md](RELEASE_READINESS.md).
