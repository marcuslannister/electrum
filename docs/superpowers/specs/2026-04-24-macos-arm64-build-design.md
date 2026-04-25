# Experimental macOS ARM64 App Build Design

## Goal

Add an experimental native Apple Silicon `.app` build path for Electrum on macOS while preserving the current reproducible `x86_64` release build as the default.

This design addresses the local-build side of GitHub issue #7557, "Native Apple Silicon Support (m1, arm)." It does not claim to solve upstream release reproducibility, universal2 packaging, signing, or notarization for ARM builds.

## Context

The current macOS release path is intentionally `x86_64`:

- `contrib/osx/make_osx.sh` sets `ARCHFLAGS="-arch x86_64"`.
- `contrib/osx/pyinstaller.spec` sets `target_arch='x86_64'`.
- `contrib/osx/README.md` states that the script is only tested on Intel Macs and targets `x86_64`.

Issue #7557 shows the primary upstream constraint: reproducibility. Maintainers disabled universal/native behavior because some compiled `.so` outputs, especially around `hidapi`, were not reproducible when built as universal binaries. The experimental ARM build must not weaken the existing `x86_64` release path.

## Architecture

Introduce a single build selector:

```bash
ELECTRUM_MACOS_ARCH=x86_64|arm64
```

The default remains `x86_64`. When set to `arm64`, the build script and PyInstaller spec must consistently use ARM settings:

- `ARCHFLAGS="-arch arm64"` for Python native extension and native library builds.
- `target_arch='arm64'` for the PyInstaller executable.
- Architecture-specific cache and DLL output directories, for example `.cache/dlls-arm64`, to prevent reuse of stale `x86_64` libraries.
- Architecture-specific unsigned DMG output, for example `electrum-$VERSION-arm64-unsigned.dmg`.

## Components

### Build Script

`contrib/osx/make_osx.sh` should validate `ELECTRUM_MACOS_ARCH` before doing any build work. Only `x86_64` and `arm64` are accepted. The script should derive `ARCHFLAGS`, cache paths, DLL target paths, and output filenames from the selected architecture.

The script should keep current `x86_64` behavior as close as possible to reduce release-build risk.

### PyInstaller Spec

`contrib/osx/pyinstaller.spec` should read `ELECTRUM_MACOS_ARCH` from the environment and pass it to `EXE(... target_arch=...)`. It should fail early for unsupported values instead of silently falling back to another architecture.

### Native Libraries

The selected architecture must apply to all app-bundled native libraries:

- `libsecp256k1`
- `libzbar`
- `libusb`
- Python native extensions such as `hidapi`
- PyQt/Qt Mach-O files bundled by PyInstaller

For ARM builds, the app must use an ARM Python runtime, ARM PyInstaller bootloader, and ARM-compatible bundled libraries. A successful build is not valid if the top-level app executable is ARM but required bundled libraries are `x86_64` only.

## Validation

After PyInstaller finishes, the build should inspect the app executable and bundled Mach-O files with `file` or `lipo -info`.

For `ELECTRUM_MACOS_ARCH=arm64`, validation must fail if any required app executable, `.so`, or `.dylib` lacks `arm64` support. Universal files are acceptable if they include `arm64`; `x86_64`-only files are not.

For `ELECTRUM_MACOS_ARCH=x86_64`, validation must preserve current behavior and fail if required artifacts lack `x86_64`.

## Error Handling

The build should fail early for:

- Unsupported `ELECTRUM_MACOS_ARCH` values.
- Reused native dependency caches from a different architecture.
- Missing PyInstaller bootloader for the requested architecture.
- Bundled Mach-O artifacts that do not contain the requested architecture.

Failures should name the offending file and expected architecture.

## Documentation

Update `contrib/osx/README.md` to document:

- The default release path remains `x86_64`.
- `ELECTRUM_MACOS_ARCH=arm64 ./contrib/osx/make_osx.sh` is experimental.
- ARM builds are intended for local Apple Silicon testing.
- Issue #7557 remains open until reproducibility, signing, notarization, and release-process questions are resolved.

## Testing Plan

Use fast checks where possible:

- Validate accepted and rejected `ELECTRUM_MACOS_ARCH` values.
- Confirm `pyinstaller.spec` receives and validates the selected architecture.
- Run a local ARM build attempt on Apple Silicon if permissions and downloads are available.
- After a successful ARM build, run architecture validation over the app bundle.
- Run the existing Python test suite to ensure the source tree remains healthy.

The full packaging build may require network downloads, Homebrew packages, and `sudo installer` for the pinned Python package. If that cannot run in the current environment, record the blocker and verify the shell/spec logic separately.

## Non-Goals

- Do not implement universal2 builds in this phase.
- Do not change release signing or notarization behavior.
- Do not claim byte-for-byte reproducibility for ARM builds.
- Do not change the default `x86_64` release target.
