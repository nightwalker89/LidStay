# LidStay Project Notes

## Build & Packaging

- Local native build + install to `/Applications/LidStay.app`:
  - `./build.sh`
- Universal binary build (`arm64` + `x86_64`):
  - `./build.sh --universal`
- Supported environment overrides in `build.sh`:
  - `UNIVERSAL=1` - build fat binary for `arm64` and `x86_64`
  - `APP_OUT_DIR` - output directory for `LidStay.app` (defaults to `/Applications`)
  - `APP_VERSION` - overrides `CFBundleShortVersionString` in the built bundle
  - `BUILD_NUMBER` - overrides `CFBundleVersion` in the built bundle

## Release & CI Verification Workflow

- CI workflow: `.github/workflows/release.yml`
  - `build-universal` (`macos-15`): builds Universal `.app` (`arm64` + `x86_64`), packages `.zip`, `.dmg`, and `SHA256SUMS.txt`, and verifies the `arm64` runtime via `./scripts/verify_runtime.sh`.
  - `test-intel` (`macos-15-intel`): downloads the exact Universal `.zip`/`.dmg` artifacts, runs `./scripts/verify_runtime.sh --arch x86_64 --expect-universal --require-live-launch` natively on Intel, and also builds & verifies a native Intel binary from source.
  - `release` (`macos-15`, `v*` tags only): publishes the GitHub Release via `gh release create` only after both `build-universal` and `test-intel` pass.
- Local runtime verification (works on Apple Silicon for both native `arm64` and Rosetta `x86_64`):
  - `./scripts/verify_runtime.sh --arch arm64 --expect-universal /path/to/LidStay.app`
  - `./scripts/verify_runtime.sh --arch x86_64 --expect-universal /path/to/LidStay.app`
- In-app runtime self-test flag: `LidStay.app/Contents/MacOS/LidStay --self-test`
- Triggers on `push` to `main` (build & Intel runtime verification), `pull_request`, `workflow_dispatch`, and `v*` tags (full release).
- To publish a release:
  1. Update `CFBundleShortVersionString` in `Resources/Info.plist` to match the release version if needed.
  2. Tag and push:
     ```bash
     git tag -a vX.Y.Z -m "Release vX.Y.Z"
     git push origin vX.Y.Z
     ```
  3. Workflow builds the Universal `.app`, verifies both `arm64` and `x86_64` Intel runtimes, packages `.zip`, `.dmg`, and `SHA256SUMS.txt`, and publishes the GitHub Release via `gh release create`.

## Localization & Privacy

- All widget UI copy (`EN` / `VI`) lives in `Sources/LidStay/Localization.swift`.
- Update both `docs/images/widget-preview-en.png` and `docs/images/widget-preview-vi.png` if widget layout or UI copy changes.
- Keep commits free of personal identifiers or private emails (use `38405415+nightwalker89@users.noreply.github.com`).
