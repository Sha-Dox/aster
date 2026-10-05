# Privacy and data handling

This document describes the current implementation, not a provider consent policy or an independent security certification.

## On your Mac

Aster caches messages, local drafts, queued edits and copied attachments under `~/Library/Application Support/Aster/`. Accounts have separate stores. App preferences use UserDefaults; OAuth state and model API credentials use macOS Keychain. Storage permissions are restricted to the current user. Cached mail is not independently encrypted; use FileVault for disk protection.

Disconnecting an account retains its local cache and attachment copies. A complete in-app data deletion flow is still pending. Close Aster before manually deleting local data. Removing an account's local files does not delete its remote mailbox.

## Network activity

Connecting Microsoft or Google uses the respective OAuth service. Reading, synchronizing, changing folders and sending mail use Microsoft Graph or Gmail API. Provider authorization and retention policies apply.

Apple Intelligence generation uses the on-device Foundation Models framework when available. Choosing a cloud or local model endpoint sends writing instructions, preferences, relevant email addresses and bounded cached conversation content to that endpoint only when a model action is requested. A new-message Formalise action uses the selected text without conversation context. Attachment contents are not included in these model prompts. Review the chosen endpoint's own privacy policy.

Aster has no app telemetry or analytics pipeline. The public repository contains fictional demo messages and test fixtures, not account exports or embedded OAuth credentials.

## Keep public reports safe

Never publish real mail, OAuth state, tokens, API keys, mailbox exports or signing material. Use fictional messages and `example.com` / `example.edu` addresses when sharing reproductions.
