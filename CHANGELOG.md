# Changelog

## Unreleased

- Compact local pane headers by removing visible positional labels, retaining a blue active-folder title, and placing navigation controls beside the path.
- Reveal current-folder search on demand with a button or Command-F, adapt it to narrow/wide panes, and reset it on Escape or folder changes.

- Add a local right-click New submenu for folders, Word, Excel, PowerPoint, PDF, text, and Markdown documents.
- Select newly created items for inline naming, with protected file extensions, numbered defaults, and collision checks.

## 1.3.0 — 2026-11-06

- Display the active folder's disk name, used capacity, total capacity, available capacity, and a usage bar in the main window.
- Refresh capacity when switching panes or folders, refreshing, completing file operations, returning to the app, and every 30 seconds while the main window is visible.

## 1.2.1 — 2026-11-05

- Prompt for SSH host verification during the first Connect or SSH Terminal action, then continue the requested action after confirmation.
- Recognize existing host trust entries for default ports, custom ports, and hashed hostnames.
- Preserve the initial remote folder after a failed connection so retries use the entered path.

## 1.2.0 — 2026-10-30

- Adopt shared Apple-inspired native design tokens: cool gray ground, white unified panes, hairline separators, restrained blue focus, and accessible header material.
- Add a separate FTP/explicit-FTPS/SFTP workspace with directory navigation, uploads, downloads, cancellation, and per-batch completion feedback.
- Add saved non-secret profiles, optional macOS Keychain passwords, explicit SSH fingerprint trust, and a Terminal-based SSH session launcher.
- Keep credentials out of configuration files, command arguments, and terminal scripts; add an authentication-only bundled helper.
- Add remote unit and disposable localhost integration tests.
- Scope file-changing menu actions to the main window, preventing remote-window shortcuts from acting on hidden local selections.

## 1.1.0 — 2026-10-30

- Translate all app-authored interface strings, menus, tooltips, alerts, metadata labels, and errors into English.
- Provide English usage, architecture, contribution, roadmap, and release documentation.
- Add a standalone test script and GitHub Actions builds for Apple silicon and Intel targets.
- Make build architecture, output directory, compiler cache, and bundle version configurable.
- Preserve the initial file-operation behavior and regression coverage.

## 1.0.0 — 2026-10-30

Initial local prototype: two/four panes, filesystem navigation, hidden items, current-folder filtering and sorting, favorites, clipboard and cross-pane operations, new folder/rename/Trash, and Quick Look. Included 36 filesystem checks and initial manual UI verification on Apple silicon/macOS 15.7.3.
