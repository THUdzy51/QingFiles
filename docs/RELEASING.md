# Releasing QingFiles

Use semantic versioning: patch for fixes, minor for compatible features, major for intentional breaking behavior. Do not claim a feature is shipped until it works and is validated.

1. Update `CHANGELOG.md`, the default version in `build.sh`, and the About dialog in `App.swift`. Keep README requirements and limitations accurate.
2. Run `./test.sh`, build, and perform the relevant manual checks from `CONTRIBUTING.md`. Use disposable data. Record OS and architecture.
3. Commit through a feature branch/pull request for future changes. Ensure GitHub Actions passes before tagging the release commit.
4. Create the version tag and push it:

   ```sh
   git tag v1.2.0
   git push origin v1.2.0
   ```

5. Build release packages locally, or download the ZIP files from the passing tagged Actions run. For local builds:

   ```sh
   QINGFILES_VERSION=1.2.0 QINGFILES_ARCH=arm64 ./build.sh
   ditto -c -k --sequesterRsrc --keepParent dist/QingFiles.app dist/QingFiles-1.2.0-arm64.zip
   ```

   Repeat with `QINGFILES_ARCH=x86_64` if providing an Intel build. Distinguish cross-compiled targets from runtime-tested targets.

6. Write release notes explaining user-visible changes, available architectures, actual validation, limitations, and signing/notarization status. Create a GitHub Release and attach the packages. Example with an authenticated GitHub CLI:

   ```sh
   gh release create v1.2.0 dist/QingFiles-1.2.0-arm64.zip --title 'QingFiles 1.2.0' --notes-file release-notes.md
   ```

7. Download/extract the uploaded artifact and verify the bundle signature and version. Link it from the release. GitHub provides source archives automatically.

The build workflow builds/tests but does not automatically publish releases. Review changes before publishing. CI architecture matrix values select compilation targets; test execution uses the runner host architecture.

## Signing

Current builds are ad-hoc signed for integrity and are not notarized. Do not describe them as Apple-certified. Developer ID signing and notarization require a separate Apple developer workflow and are not included yet.

## Preview build isolation

Release Info.plist files must not contain `QingPreviewPath`, `QingSnapshotPath`, or other fixture-specific keys. Do not publish screenshots containing personal folder names or credentials.
