# Release readiness — Aster 0.7

The current package is an expanded development release. It is not certified for production replacement of an existing mail client.

## Verified locally

- Release executable builds with Swift 6.3.3 / Xcode 26.6 on macOS 26.6.2, Apple silicon.
- 57 automated regression tests pass. Four additional hardware-dependent Apple Intelligence tests are skipped in the baseline suite and passed in a separate opt-in run using actual on-device inference, including a professor reply choosing A and substituting Thursday for Monday, selected rough text becoming a complete formal email with a saved sender name, and a request-focused annual-estimate summary.
- Regression coverage includes durable offline queues, stale-edit merging, FTS escaping, paged 1,200-message cache access, Gmail labels/history/snapshot recovery, draft IDs, preserved draft attachment bytes, MIME Bcc and injection protection, one-time credential refresh, bounded retry policy, Graph ID mapping and folder-scoped tombstones. Multi-account coverage checks colliding IDs, correct reply ownership, isolated Junk moves, retained reader selection, offline draft retention, policy persistence, archived/Junk inclusion and clearing replied-thread hints. Reply-assistant tests check that generation only creates a preview, explicit acceptance sends the edited text, accepted previews cannot be sent twice or through another account, user intent/style reach the adapter, and legacy account policies still decode.
- Formalisation regression coverage verifies Unicode selection boundaries, selected-only instructions, formal style, JSON subject/body output, retained recipients/subjects, no generation side effects, and explicit sending of the reviewed body. Clear glass now uses transparent window backing and a native desktop blur; clear/frosted/solid settings and accessibility fallbacks are supplied.
- Personalization tests verify workspace defaults, independent account overrides, explicit unnamed accounts, old preference decoding, signature precedence and repaired placeholders. Window checks verify normal level, disabled body dragging and a passive backdrop. Summary coverage includes prose requests with annual units and optional empty details; on-screen focus behavior remains unverified.
- Apple Development signing with hardened runtime is available for local testing. The packaged framework and app signatures are checked during packaging.
- GitHub Actions runs regression tests and app packaging on a hosted macOS 26 runner. Tests and release packaging passed on the initial hosted run; check the README workflow badge for complete run status. Developer ID/notarization scripts are supplied.

## Required before production distribution

| Gate | Current state | Acceptance evidence |
| --- | --- | --- |
| Microsoft live integration | Unverified; Entra client ID required | Two simultaneous addresses, sign-in, silent refresh, isolated sign-out, tenant policy, full/delta sync, reply, attachment, draft and deliberate test send against dedicated Microsoft accounts |
| Gmail live integration | Unverified; Desktop OAuth client required | Two simultaneous Google addresses plus mixed Microsoft/Google sessions, browser PKCE, refresh persistence, labels/history expiry, draft replacement, attachments and deliberate test send against consumer and Workspace accounts |
| New visual and accessibility QA | Compact workspace and interaction fixes build; on-screen inspection blocked by desktop capture failure/timeouts; manual focus, text-selection and full visual/accessibility pass pending | Inspect Liquid Glass in light/dark, increased contrast/reduced transparency, keyboard focus, VoiceOver, small window layouts and composer autosave, unified reader, per-account settings and instruction → editable preview → acceptance flow |
| Google public OAuth verification | Pending | Required restricted-scope consent verification and any applicable security assessment, plus published privacy policy |
| Public signing and notarization | Pending | Developer ID signature, entitlement review, Apple notary acceptance, stapled ticket and Gatekeeper assessment on a clean Mac |
| Mailbox scale and recovery | Partially covered with synthetic tests | Real large mailboxes, network loss, terminated sync, token expiry, quota/throttling, draft crash recovery and send-uncertainty recovery walkthrough |
| Security and privacy review | Pending | Independent review of token storage, HTML isolation, MIME handling, attachment retention, dependencies and data deletion |
| Deployment matrix | Only current Apple silicon Mac tested | Supported earlier macOS versions, model unavailable states, Intel build if supported and clean-install/upgrade validation |

## Product limits

Multiple simultaneous Microsoft/Google accounts and a unified Priority inbox are implemented. Live multi-account OAuth persistence and concurrent provider use remain unverified. No IMAP, push notifications, bulk operations, server-side search, semantic search or automatic offline sends. Attention cues primarily recognize English text. Original HTML is isolated but inline CID images are not resolved. Full initial sync caches message bodies. Outgoing attachments are limited to 3 MB each / 20 MB total and copied files are retained locally. Attachment selections autosave locally; upload occurs on Send. Remote saved drafts do not automatically receive selected local files until Send.

Provider failures preserve cache and local drafts. Ambiguous sends block automatic repeats of that composer, but a user-facing reconciliation workflow is still needed. Draft creation after an ambiguous transport failure can leave a remote duplicate draft and must be checked during live testing. Model outputs require human review.

## Credentials needed to finish live validation

Create dedicated Microsoft and Google OAuth applications using the README steps, then connect test accounts from Settings. Public releases additionally need the project's Developer ID signing identity and configured notarytool profile. No credentials are embedded in this source or package.
