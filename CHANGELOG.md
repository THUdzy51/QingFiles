# Changelog

## Unreleased

- Future maintenance and feature work will be recorded here.

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
