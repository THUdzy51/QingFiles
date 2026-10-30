# Contributing

Small, focused changes are easiest to maintain. Start with an issue describing the user-visible problem, expected behavior, and scope. For larger features, discuss filesystem semantics before implementing the interface.

## Development loop

```sh
./test.sh
./build.sh
open dist/QingFiles.app
```

Use Swift 5 language mode as configured by the scripts, with a macOS 13 deployment target. Write project documentation, comments, menus, tooltips, and app-authored errors in English. Keep user file names unchanged.

## Validation checklist

- Run `./test.sh` when changing operations or shared models.
- Run the disposable loopback integration suite from `docs/REMOTE_CONNECTIONS.md` when changing remote adapters or credentials. Never use a real server for regression fixtures.
- Add regression checks for meaningful behavior changes, especially collision, symlink, and partial-failure behavior.
- Test mutations only in a disposable fixture directory.
- Check both two-pane and four-pane layouts, including the minimum window size.
- Check path/search text editing and file keyboard shortcuts separately.
- Verify background listings cannot expose stale selections after navigation.
- Update README/guide and CHANGELOG for user-visible changes.
- State which macOS version and architecture were actually tested.

Never silently introduce overwrite, permanent delete, or elevated permissions. A new overwrite feature needs explicit interaction design and dedicated regression coverage. Avoid copying proprietary artwork, branding, or source code.

## Reporting problems

Include the macOS version, Mac architecture, QingFiles version, reproduction steps, expected/actual result, and whether the folder is local, removable, or network-mounted. Remove private paths and file contents from screenshots and logs.

## Pull requests

Explain the concrete trigger and resulting behavior, relevant implementation choices, and validation performed. Reference a related issue when available. Prefer a feature branch and a reviewable pull request over unrelated edits bundled together.
