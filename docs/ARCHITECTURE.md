# Architecture

QingFiles is a small AppKit application compiled directly with `swiftc`. There are no external dependencies, generated UI files, Xcode project, or Swift package manifest.

## Code map

| File | Responsibility |
|---|---|
| `App.swift` | Entry point, menus, main window, sidebar, pane pairing, clipboard intent, operation queue, alerts, persistence, Quick Look controller. |
| `FilePane.swift` | Independent directory browser: table, navigation history, path/search fields, selection, sorting, context menu and keyboard routing. |
| `FileService.swift` | Local filesystem metadata and mutations, name validation, collision prevention, selection validation, and per-item results. |
| `RemoteService.swift` | Validated profiles/paths, process runner/cancellation, FTP MLSD and SFTP listing parsers, curl/OpenSSH adapters, host trust, and Keychain credentials. |
| `RemoteWorkspace.swift` | Grouped connection form and separate local/remote browsing, transfers, profile saving, fingerprint consent, and SSH Terminal launcher. |
| `Tools/Askpass.swift` | Authentication-only SSH_ASKPASS helper; never handles host trust. |
| `Theme.swift` | Shared colors, labels/buttons, favorite row appearance, top-aligned sidebar stack. |
| `Tools/MakeIcon.swift` | Draw the original application icon with AppKit. |
| `Tools/PackIcon.swift` | Package icon PNG representations into ICNS. |
| `Tests/FileServiceTests.swift` | Standalone temporary-directory filesystem regression suite. |
| `build.sh` / `test.sh` | Reproducible native build and test entry points. |

## Browsing flow

A `FilePane` requests a directory listing on a background queue. Each request carries a generation number. Late results from older requests are ignored. Changing folders clears previous rows immediately; loading panes do not export an old selection for file actions. Filtering and table updates happen on the main queue.

The pane delegates mutation requests to the application controller through `onAction`. Browsing, opening documents, and outbound drag data are handled by the pane. Filesystem mutations belong in `FileService`, not in table-cell code.

## Operation flow

1. The controller captures selected source URLs and the destination URL.
2. Copy/move/Trash work is queued on a serial background operation queue.
3. `FileService` validates the operation and processes items without replacing existing destinations.
4. A report returns successful URLs and failures with their source URL and message.
5. The controller refreshes panes and reports incomplete items on the main queue.

Batches are not transactional: earlier successes are not rolled back when a later item fails. Small create/rename operations currently run from the UI action; consider moving them to the operation queue if remote-mounted or slow volumes become a priority.

## Clipboard

Cut intent is tracked with the pasteboard change count. If another application replaces the clipboard, old cut intent no longer applies. After a partial move-paste, only failed sources remain prepared for retry. Clipboard synchronization and other applications can still change pasteboard contents; test these interactions when changing clipboard behavior.

## Quick Look

The window delegate participates in the preview panel controller lifecycle. Data source/delegate are installed in `beginPreviewPanelControl` and removed in `endPreviewPanelControl`. Do not mutate preview state before obtaining control.

## Permissions and boundaries

This is an unsandboxed, ad-hoc-signed desktop application using the current user's permissions. It does not request administrator access. macOS privacy permissions and read-only system locations still apply.

Remote connections are explicitly initiated in a separate workspace using macOS curl/OpenSSH; no analytics is included. See REMOTE_CONNECTIONS.md for password and host-key handling. Opening a file invokes its system default application, which has its own behavior. Symlink and collision checks reduce common mistakes; they are not a transactional filesystem or a defense against every concurrent modification race.

## UI verification fixtures

The app accepts `--preview PATH --snapshot OUTPUT.png` for developer smoke checks. The fixture must contain `Workspace`, `Library`, `Workspace/Climate Research`, and `Library/Paper Notes`, including `Workspace/README.md`. A separately packaged QA copy can set `QingPreviewPath` and `QingSnapshotPath` in its Info.plist for Launch Services testing. Preview mode does not save normal user preferences. These keys must not be added to release bundles.
