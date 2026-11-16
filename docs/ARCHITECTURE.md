# Architecture

QingFiles is a small AppKit application compiled directly with `swiftc`. There are no external dependencies, generated UI files, Xcode project, or Swift package manifest.

## Code map

| File | Responsibility |
|---|---|
| `App.swift` | Entry point, menus, main window, sidebar, pane pairing, clipboard intent, operation queue, alerts, persistence, Quick Look controller. |
| `FilePane.swift` | Independent directory browser: table, navigation history, path/search fields, selection, sorting, context menu and keyboard routing. |
| `FileService.swift` | Local filesystem metadata and mutations, name validation, collision prevention, selection validation, and per-item results. |
| `FileRevealService.swift` | Decode local file URLs and legacy filename lists supplied to the macOS service. |
| `WeChatRevealSetting.swift` | Persist WeChat's viewer override and its restoration record, with verified writes and protection for externally changed preferences. |
| `SettingsWindow.swift` | Native settings window with an opt-in WeChat reveal switch, asynchronous preference access, and save/error feedback. |
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

## External file reveal

`build.sh` declares supported document types with the Viewer role and Alternate handler rank. `QingAppDelegate.application(_:open:)` queues requests received before the main window exists. File URLs are validated by `FilePane.revealFiles`, then navigated and selected in the active pane. Selection survives activation refreshes until the current listing finishes. Navigating elsewhere invalidates it. Explicitly revealed hidden items are included individually, and listing URLs retain the caller’s logical directory spelling. Same-folder batches are supported.

The main app delegate provides the registered Reveal in QingFiles service after the window is ready. Its pasteboard decoder accepts modern file URLs and legacy filename arrays. A single ordinary directory opens directly, while documents and packages are selected in their parent. The service title has a Simplified Chinese localization in `Resources/zh-Hans.lproj/ServicesMenu.strings`.

The optional WeChat integration writes only `NSFileViewer` in WeChat's sandbox preference domain through `/usr/bin/defaults`. QingFiles stores the previous optional string before writing the override and verifies the resulting value. Disable restores that backup only while the override still belongs to QingFiles, then clears the backup. The settings controller serializes reads and changes off the main thread. WeChat must be fully restarted to load a changed preference; a temporary command-line override takes precedence until that process exits.

## UI verification fixtures

The app accepts `--preview PATH --snapshot OUTPUT.png` for developer smoke checks. The fixture must contain `Workspace`, `Library`, `Workspace/Climate Research`, and `Library/Paper Notes`, including `Workspace/README.md`. A separately packaged QA copy can set `QingPreviewPath` and `QingSnapshotPath` in its Info.plist for Launch Services testing. Preview mode does not save normal user preferences. These keys must not be added to release bundles.

## Blank documents and inline naming

`FileService.createBlank` uses exclusive file writes (or directory creation), retrying numbered names only on an existing-item error. Original blank Office and PDF documents live in `Resources/BlankDocuments` and are copied into the application bundle by `build.sh`. `Tools/GenerateBlankDocuments.py` can regenerate these resources with development-only python-docx, openpyxl, and python-pptx dependencies. Normal builds use the checked-in resources directly.

The controller captures the originating pane and directory before resigning a field editor and queues creation on its operation worker. The pane clears its filter, waits for its current listing generation, selects the returned URL, and starts inline editing only while still active in the key window. Inline naming preserves the file extension and delegates collision checks to `FileService.rename`. Refreshes of an editing pane are deferred until editing finishes.

## Pane path interaction

The path bar uses separate buttons for directory names and their subfolder menus, plus a text field for full-path editing. Buttons retain their original URLs, including symbolic-link spelling. Middle segments collapse into an overflow menu. Subfolder menus use the same directory listing and hidden-item rules as the file pane and load off the main thread. Both kinds of menu and direct segment clicks use the existing navigation history. Only Return submits text. Escape and blur restore breadcrumb mode. Destination validation precedes navigation, and field-editor resignation precedes history mutation.
