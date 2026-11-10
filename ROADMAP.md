# Roadmap

These are proposed directions, not release commitments. Track implementation in GitHub issues and record shipped behavior in CHANGELOG.

## Reliability and usability first

- Directory watching with bounded refresh work.
- Persisted transfer results, progress, and cancellation semantics.
- Undo where a reliable inverse operation is possible.
- Inbound drag and drop with an explicit copy/move policy.
- More permission, removable-volume, and large-directory validation.
- Automated UI regression coverage for focus and pane pairing.

## Workspace improvements

- Tabs and an optional folder tree.
- Resizable pane dividers and saved workspace layouts.
- User-customizable shortcuts and a command palette.
- Batch rename with a preview before applying changes.

## Larger features requiring design

- Archive browsing and extraction with traversal protection.
- Recursive remote transfers, resume support, jump hosts, and broader server compatibility.
- Embedded terminal sessions beyond the current system Terminal launcher.
- Cloud-provider integration with clear sync semantics.
- Developer ID signing, notarization, and an update mechanism.

Before adding new providers, define error recovery, partial operations, credential handling, and the test strategy.
