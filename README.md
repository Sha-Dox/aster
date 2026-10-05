# Aster

[![macOS checks](https://github.com/Sha-Dox/aster/actions/workflows/ci.yml/badge.svg)](https://github.com/Sha-Dox/aster/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![SwiftUI](https://img.shields.io/badge/SwiftUI-native-orange)

A native, open-source macOS mail client for Microsoft 365, Outlook, Gmail and Google Workspace. SwiftUI, SQLite, Microsoft Graph, Gmail API, MSAL and AppAuth. Original messages remain central; an attention briefing helps you decide what to read next.

Version 0.6 provides instruction-driven email previews, customizable writing language and style, multiple simultaneous accounts, a unified Priority inbox, per-account inbox and Junk controls, native Liquid Glass surfaces, on-device Apple Intelligence, Google authentication and synchronization, durable offline changes, paged cached mail, autosaved local drafts, Bcc and outgoing attachments. It is a substantially expanded development release. See [release readiness](RELEASE_READINESS.md) for the remaining production gates.

## Run and build

Build the app from source and choose **Explore the demo** to try fictional inboxes without connecting an account. Demo sends only update the local demo Sent folder. Account caches are separate.

Requires macOS 14 or later; Liquid Glass and Apple Intelligence require macOS 26. Build with Xcode 26 or newer and its command line tools selected. Apple Intelligence additionally requires supported hardware and the system model enabled. No signed public binary is included in this repository.

```sh
git clone https://github.com/Sha-Dox/aster.git
cd aster
swift test
./scripts/build-app.sh
open ../Aster.app
```

Use the packaged app for OAuth; its bundle identity and redirect scheme are required. Exact MSAL 2.5.0 and AppAuth 2.0.0 revisions are recorded in `Package.resolved`. The packaging script builds for the current host architecture; Intel support remains unvalidated.

## Connect Microsoft

1. Register a public-client app in Microsoft Entra supporting the desired organizational and/or personal accounts. The current authority is `common`.
2. Add a Mobile and desktop redirect URI: `msauth.app.aster.mail://auth`. Enable public-client flows as required by your tenant.
3. Add delegated Graph permissions `Mail.ReadWrite`, `Mail.Send`, `User.Read`. Your organization may require administrator consent.
4. Enter the application ID in Settings and select **Connect Microsoft**. No Microsoft client secret belongs in the app.

MSAL manages authentication tokens. Cached mail stays readable when reconnection is required. Validate tenant policies and Keychain persistence with your signing identity before deployment. [Microsoft configuration documentation](https://learn.microsoft.com/en-us/entra/msal/objc/install-and-configure-msal).

## Connect Gmail

1. Create a Google Cloud project, enable Gmail API and configure the OAuth consent screen. Add your account as a test user while the project is in testing.
2. Create an OAuth client of type **Desktop app**. Enter its client ID and issued desktop client secret, if present, in Settings.
3. Select **Connect Google** and finish authorization in your browser. AppAuth uses PKCE, state verification and a temporary loopback callback. A desktop client secret cannot be treated as confidential.
4. Request the `gmail.modify` scope, which supports reading, drafting, sending and recoverable label changes. The app does not call permanent-delete endpoints.

Google public distribution requires applicable OAuth verification for this restricted scope; testing-mode refresh credentials may expire under Google's testing policies. See [native OAuth](https://developers.google.com/identity/protocols/oauth2/native-app) and [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes). Google Workspace administrators can impose additional access restrictions.

## Multiple accounts and inbox control

Connect as many Microsoft or Google addresses as needed from **Accounts & controls**. Each address keeps its own authenticated session, SQLite database, offline queue, drafts and policies. Every connected account synchronizes independently; one failed account does not stop the others. The top account selector switches between individual mailboxes and **All accounts · Priority**. Unified rows display the receiving address and replies use that account. New messages show a From address; choose the sending account before composing.

Settings → **Inbox controls · per account** lets you configure each address:

| Setting | Behavior |
| --- | --- |
| Important mail | Local attention hints, starred mail and your priority senders |
| Entire inbox | Every Inbox message, including ordinary updates |
| All received mail | Inbox, archive and custom folders in one Priority view; Sent, Drafts and Trash stay separate |
| Junk: Keep separate | Junk remains outside Priority |
| Junk: Show in Priority | Includes cached Junk without changing its folder on the server |
| Junk: Move to Inbox on sync | Moves existing and newly synced Junk to Inbox while Aster is running, using the durable mutation queue |
| Hide Junk / visible folders | Changes which folders appear in this app’s sidebar |
| Always prioritize senders | Adds exact sender email addresses to Important mail; comma-separated |

To combine all received mail for one account, select the address and click **All mail in Priority · include Junk**. This enables All received mail, includes Junk, and hides the separate Junk folder for that account. Other addresses keep their own settings.

Automatic Junk recovery changes server mailbox placement, but does not disable Gmail/Microsoft spam filtering, bypass administrator policy, or recover mail quarantined outside the accessible mailbox. It runs during app synchronization, not as a permanent server rule. Provider references: [Gmail label management](https://developers.google.com/workspace/gmail/api/guides/labels), [Graph move](https://learn.microsoft.com/en-us/graph/api/message-move). No mailbox rules or provider-wide filtering settings are silently changed.

Search in the unified view queries every account’s cached Priority mail, with up to 1,000 matches per account. Loading older mail extends each account page. Provider message and thread IDs are scoped to their account to prevent collisions. The demo includes two addresses with different Priority settings, plus Junk and archived examples.

## Daily mail features

- Folder and Gmail label browsing, cached original messages, thread reading, local full-text search, and incremental synchronization.
- Mailbox pages load 500 messages at a time; **Load older** extends the view. Search queries the entire cache with up to 1,000 results. Thread selection loads its cached conversation independently of the visible page.
- Gmail history and Microsoft folder delta checkpoints commit with their pages. Expired cursors rebuild a snapshot while retaining readable cache until reconciliation completes.
- Read/unread, star/flag, archive, folder moves and recoverable trash. Offline mutations persist in SQLite, merge with incoming updates and retry after reconnection.
- Reply, reply all, forward, Bcc, local draft autosave and explicit remote draft saving. Local drafts preserve reply context and attachment selections across reopening.
- Outgoing files up to 3 MB each and 20 MB total. Selected files are copied into private app storage. Attachments are uploaded on Send; local autosave does not upload them. Editing a Gmail draft preserves existing attachments.
- Incoming attachment downloads through a Save dialog. HTML blocks scripts, forms, remote images and automatic navigation. User-clicked links open externally.
- Command palette, keyboard navigation, native menus, light/dark appearance, VoiceOver labels, reduced-transparency and increased-contrast fallbacks.

Clear Liquid Glass is the default for navigation, search, briefing and action controls. The window and composer use a native blurred desktop backdrop with transparent window backing. Settings → Appearance offers Clear glass, Frosted glass and Solid. Reduce Transparency and increased contrast use opaque surfaces. Email reading surfaces remain solid for readability. Earlier systems use native materials.

## Interface

A compact workspace bar and account rail anchor the unified inbox. Conversation cards combine sender avatars, unread indicators, receiving-account labels and attention hints. Cached unread/reply metrics provide a quick overview. The reader uses an editorial subject heading, individual message surfaces and focused reply/AI actions. Glass surfaces sit over a tinted desktop blur; solid and accessibility fallbacks remain available.

## Select text and formalise it

In a new message or reply composer, type your rough answer, select the text and click **Formalise** (also available in the selection’s context menu). For example: “I choose A, but change Monday to Thursday. Ask if that works.” Only the selected text is sent as your writing instruction; replies also supply cached conversation context.

The reply assistant also has a selection-based **Formalise** button. It uses only the selected rough answer and forces formal tone; **Generate preview** continues to use the whole instruction and your chosen tone.

Review the complete formal email in the editable preview. **Use full email** replaces the whole draft body; **Accept & send** sends the reviewed email. Cancel retains the original draft. Recipients, attachments and an existing subject are preserved; an empty subject gets a generated subject. Language, length, custom instructions and signature use your account’s writing preferences; Formalise always uses formal tone. Generation alone does not save a remote draft or send mail.

## Turn a short instruction into a complete reply

Select a conversation and click **Write with AI** (⇧⌘W). Tell the assistant what you want to say, for example: “Choose A, but replace X with Y. Ask whether that works.” The assistant uses the selected message and its cached thread to write a full reply with a greeting, answer and closing.

1. Enter your decision and any substitutions or requests.
2. Choose the language, tone (professional/formal/friendly/casual), length, custom writing instructions and signature. You can match the original language or type another language; support depends on the model.
3. Click **Generate preview**. Generation does not create a remote mail draft or send an email.
4. Review and edit the From/To/Cc context, subject and complete body. The receiving account supplies the reply sender. From is fixed to that account; editable recipients are validated at Send.
5. Click **Accept & send** to deliver the exact reviewed text through that account, or **Save draft & close** to retain it locally without sending.

Changing your instruction or style requires regeneration before acceptance. A generated preview is tied to its account/session and cannot be accepted twice. After a send attempt, regeneration is paused; ambiguous sends retain the durable no-repeat protection. Check Sent before deliberately creating another reply after an uncertain result.

Settings has default writing preferences and overrides for each address. You can also click **Remember this style for this address** inside the assistant. Your intent decides the answer; style preferences affect how it is written. Without a signature, the model is instructed to use a name placeholder rather than invent your name. Review all names, substitutions and dates before accepting.

Apple Intelligence runs the writing on-device when available. A configured remote endpoint receives the intent, writing preferences, sender address and cached conversation only when you request generation. Local rules alone cannot generate an instructed email. Cached/model context may be incomplete or shortened; no attachment contents are read by this assistant. Live provider sending remains unverified.

## Apple Intelligence and other models

Apple Intelligence is the default provider. Explicit **Summarize** and **Draft a reply** actions run through Apple's on-device Foundation Models framework on supported macOS 26 hardware with the system model available. Settings reports unavailable, disabled or downloading states. When unavailable, contextual notes fall back to clearly attributed local rules. An actual on-device summary integration test passed on the development Mac.

AI uses a bounded selection of the cached conversation, which may be incomplete. Generated replies remain editable and require Send. Email is treated as untrusted input; output can still be inaccurate. No automatic AI sends or background model uploads are implemented.

**Local rules only** avoids model inference. **My cloud / local endpoint** supports an OpenAI-compatible `/v1` endpoint and a Keychain-stored API key. HTTPS is required except on localhost. Explicit model actions send conversation content and addresses to that selected endpoint; consult its privacy policy. Native Anthropic and MLX adapters are not included.

## Reliability and storage

SQLite runs in a serial actor with WAL, bound parameters, full-text indexes, durable mutation queues and snapshot reconciliation. Microsoft immutable IDs and folder-scoped tombstones protect messages after moves. Gmail labels retain multiple-folder membership. Read requests use bounded backoff for transient failures; send and draft creation are not blindly retried. A 401 permits one explicit credential refresh.

An ambiguous send records a durable uncertainty marker. Automatic resending of that composer is blocked; check the provider's Sent folder and synchronize before deliberately creating another message. This conservative behavior needs live validation across both providers.

Mail and retained attachment copies live under `~/Library/Application Support/Aster/`. Directories and files have owner-only permissions. Mail is not independently encrypted; FileVault provides disk protection. Disconnect retains cached mail and attachment copies. To purge them, close the app and remove the appropriate cache and attachment files. OAuth credentials and API secrets are stored in Keychain. There is no telemetry pipeline.

## Architecture

| Area | Implementation |
| --- | --- |
| UI and Liquid Glass | `Sources/Aster/*View.swift`, `GlassDesign.swift` |
| Multi-account coordination and unified UI | `WorkspaceState.swift`, `WorkspaceView.swift` |
| State, autosave and lifecycle per account | `AppState.swift` |
| Account profiles and Priority policies | `AccountPolicy.swift` |
| OAuth and Keychain | `Auth.swift`, `GoogleAuth.swift` |
| Provider abstraction | `MailBackend.swift` |
| Graph and Gmail | `GraphClient.swift`, `GmailClient.swift` |
| Safe transport and retry policy | `HTTPTransport.swift` |
| Local persistence and attention indexes | `MailStore.swift` |
| MIME, addressing and attachments | `MIME.swift`, `OutgoingAttachment.swift` |
| On-device and optional remote AI | `AppleIntelligence.swift`, `RemoteIntelligence.swift`, `ReplyWriting.swift` |
| Instruction, editable preview and acceptance UI | `ReplyAssistantView.swift` |

## Release and verification

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build-app.sh
NOTARY_PROFILE='your-keychain-profile' ./scripts/notarize.sh
```

The release script signs the bundled framework and app with hardened runtime and verifies the staged bundle. Notarization requires your Developer ID and an existing notarytool Keychain profile. The default build uses ad-hoc signing for local development. Public distribution requires Developer ID signing and notarization.

CI runs tests and app packaging on macOS with Xcode 26. The hardware model test is opt-in:

```sh
ASTER_TEST_APPLE_INTELLIGENCE=1 swift test --filter AppleModelIntegrationTests
```

Remaining limits include no IMAP, push notifications, server-side search, bulk actions or automatic offline sends. Attention rules primarily recognize English cues. Cached threads do not guarantee complete server conversation history. Inline `cid:` images are not resolved and HTML uses an internal scrolling reader. Initial synchronization stores full bodies; realistic large-mailbox benchmarks and security review remain required.

MIT licensed. Third-party notices are included in source and the app bundle.

## Contributing and project information

- [Contribution guide](CONTRIBUTING.md) — development setup and pull request expectations.
- [Roadmap](ROADMAP.md) — next priorities and release gates.
- [Changelog](CHANGELOG.md) — development release history.
- [Privacy](PRIVACY.md) — local storage, authentication and explicit model requests.
- [Security policy](SECURITY.md) — report vulnerabilities privately.

All demo messages and test mail addresses are fictional. Do not attach real messages, tokens or account exports to public issues.
