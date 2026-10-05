# Security policy

Aster is a development-stage email client. Live provider validation, independent security review and public release signing are still pending. See [release readiness](RELEASE_READINESS.md).

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/Sha-Dox/aster/security/advisories/new) for issues involving credentials, mailbox access, HTML isolation, attachment handling or unintended sending. Please do not disclose an exploitable issue or private mailbox data in a public issue.

Include affected version, minimal reproduction steps using fictional mail, expected behavior and impact. Remove credentials, real email addresses, message bodies and local paths from diagnostics. There is no guaranteed response SLA at this stage.

## Supported versions

Security fixes target the latest commit on `main`. There are no supported production releases yet. Dependencies are pinned in `Package.resolved`; contributions updating dependencies should include relevant validation.
