# Release Process

Pointless uses an automated GitHub Actions pipeline to compile, package, sign, and publish binary releases.

---

## 1. Automated Release Pipeline

The release pipeline is defined in [`.github/workflows/release.yml`](../.github/workflows/release.yml).

### Triggering a Release
Releases trigger automatically upon pushing a semantic version tag:

```bash
# 1. Ensure main is up to date and clean
git checkout main
git pull origin main

# 2. Run local verification
swiftlint
swift Tests/run-tests.swift
swift test

# 3. Create and push tag
git tag v0.1.0
git push origin v0.1.0
```

You can also trigger a release manually via GitHub Actions under the **Actions > Release > Run workflow** tab.

---

## 2. Generated Release Assets

Each release attaches three assets:

1. **`Pointless.dmg`**: A compressed disk image (UDZO) containing `Pointless.app` and a symlink to `/Applications`.
2. **`Pointless.zip`**: A compressed zip archive created with macOS `ditto` preserving resource forks and bundle structure.
3. **`checksums.txt`**: SHA-256 hashes of `Pointless.dmg` and `Pointless.zip` for verification and Homebrew cask updates.

---

## 3. Homebrew Cask Updates

After publishing the release assets, the release workflow automatically:
1. Extracts the SHA-256 hash of `Pointless.dmg` from `build/checksums.txt`.
2. Updates `version` and `sha256` in `Casks/pointless.rb` via `Scripts/update-cask.sh`.
3. Commits and pushes the update directly to `main`.

To update the cask definition manually:

```bash
./Scripts/update-cask.sh <version> <dmg_sha256>
```

---

## 4. Local Packaging Scripts

You can build and test release assets locally on macOS using the repository scripts:

```bash
# Compile and package build/Pointless.app with ad-hoc signature
./Scripts/make-app.sh

# Build build/Pointless.dmg, build/Pointless.zip, and build/checksums.txt
./Scripts/make-dmg.sh
```

---

## 5. Code Signing & Gatekeeper Notes

Pointless is distributed with an ad-hoc code signature (`codesign --force --deep --sign -`).

- **Apple Silicon:** Ad-hoc signing satisfies macOS AMFI requirements, allowing native execution on Apple Silicon (arm64).
- **Gatekeeper:** When downloaded via a browser, macOS attaches the `com.apple.quarantine` attribute. On macOS 15+, users can clear this attribute via:
  ```bash
  xattr -cr /Applications/Pointless.app
  ```
  Alternatively, open **System Settings > Privacy & Security > Security** and click **Open Anyway**.
- **Notarization (Future):** When an Apple Developer ID certificate is added to the repository secrets (`APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_API_KEY`), the workflow can be updated to sign and submit for Apple Notarization via `xcrun notarytool`.
