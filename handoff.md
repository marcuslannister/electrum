# Handoff: macOS ARM64 Electrum Build Work

## Current Repository State

Repository: `/Users/ken/github/Marcus/electrum`

Branch: `master`

Local branch status before this handoff commit: ahead of `origin/master` by three documentation commits, with ARM64 implementation changes pending.

Recent local commits before the implementation commit:

- `0ed2e906f docs: clarify native macos arm64 build target`
- `f371c77ab docs: design experimental macos arm64 build`
- `efb39a49c docs: add contributor guide`

Target machine: Apple Silicon Mac, `arm64`, M4-class local build target.

## Modified Files and Key Changes

- `contrib/osx/make_osx.sh`
  - Added `ELECTRUM_MACOS_ARCH=x86_64|arm64`.
  - Kept `x86_64` as the default release-compatible path.
  - Uses the pinned python.org runtime at `/Library/Frameworks/Python.framework/Versions/3.12/bin/python3`.
  - Validates host, Python runtime, clang output, PyInstaller bootloader, and final app Mach-O architecture.
  - Uses architecture-specific caches for ARM64, such as `.cache/dlls-arm64`, `.cache/pip_cache-arm64`, and `.cache/pyinstaller-arm64`.
  - Exports `PIP_CERT` from pip's vendored certifi bundle to avoid python.org macOS TLS certificate failures during dependency installation.
  - Writes ARM64 unsigned DMGs as `dist/electrum-$VERSION-arm64-unsigned.dmg`.

- `contrib/osx/pyinstaller.spec`
  - Reads `ELECTRUM_MACOS_ARCH`.
  - Validates supported values.
  - Passes the selected architecture to `EXE(... target_arch=...)`.

- `contrib/osx/macos_arch.sh`
  - New Bash helper for architecture selection, cache/output path derivation, Mach-O inspection, Python runtime checks, clang checks, bootloader discovery, and final app bundle validation.

- `contrib/osx/test_macos_arch.sh`
  - New fast shell regression test for the helper and static integration points.

- `contrib/make_zbar.sh`
  - Links `-liconv` on macOS so ARM64 zbar builds resolve `iconv`, `iconv_open`, and `iconv_close`.

- `contrib/osx/README.md`
  - Documents the default `x86_64` path and the experimental native Apple Silicon command:

```bash
ELECTRUM_MACOS_ARCH=arm64 ./contrib/osx/make_osx.sh
```

- `docs/superpowers/plans/2026-04-24-macos-arm64-build.md`
  - Records the implementation plan used for the ARM64 build work.

## Architecture Decisions

The experimental ARM64 path preserves the existing reproducible `x86_64` macOS release build as the default.

The build selector is:

```bash
ELECTRUM_MACOS_ARCH=x86_64|arm64
```

Default behavior remains `x86_64`.

When `ELECTRUM_MACOS_ARCH=arm64`, the build must consistently use ARM settings:

- `ARCHFLAGS="-arch arm64"`
- `target_arch="arm64"` in PyInstaller
- ARM Python runtime
- ARM PyInstaller bootloader
- ARM-compatible bundled native libraries
- ARM-specific dependency caches
- ARM-specific unsigned DMG filename
- Post-build validation that all bundled Mach-O files contain `arm64`

Universal Mach-O files are acceptable only if they include `arm64`.

`x86_64`-only artifacts are not acceptable in an ARM64 build.

Do not implement `universal2` builds in this phase.

Do not change signing, notarization, or official release reproducibility claims.

Do not claim GitHub issue `#7557` is fully solved. This work only adds an experimental local native Apple Silicon build path.

## Build Result

Native ARM64 build command:

```bash
ELECTRUM_MACOS_ARCH=arm64 ./contrib/osx/make_osx.sh
```

Build output:

- `dist/Electrum.app`
- `dist/electrum-0ed2e906f-arm64-unsigned.dmg`

The DMG was unsigned and not notarized.

## Verification Status

Full test command:

```bash
env HOME=/tmp/electrum-pytest-home .venv/bin/python -m pytest tests -v
```

Latest full test result:

```text
945 passed, 6 skipped, 242 subtests passed in 192.51s
```

Fast checks run:

```bash
bash contrib/osx/test_macos_arch.sh
bash -n contrib/osx/macos_arch.sh
bash -n contrib/osx/make_osx.sh
bash -n contrib/osx/test_macos_arch.sh
bash -n contrib/make_zbar.sh
.venv/bin/python -m py_compile contrib/osx/pyinstaller.spec
git diff --check
```

Native app validation command:

```bash
bash -c 'source contrib/osx/macos_arch.sh && electrum_macos_validate_app_bundle_arch dist/Electrum.app arm64'
```

Observed ARM64 Mach-O files:

- `dist/Electrum.app/Contents/MacOS/run_electrum`
- `dist/Electrum.app/Contents/Frameworks/hid.cpython-312-darwin.so`
- `dist/Electrum.app/Contents/Frameworks/libsecp256k1.6.dylib`
- `dist/Electrum.app/Contents/Frameworks/libzbar.0.dylib`
- `dist/Electrum.app/Contents/Frameworks/libusb-1.0.dylib`

## Open Risks and TODOs

- ARM64 reproducibility is not proven.
- Signing and notarization are not addressed.
- Official release support remains unresolved until upstream reproducibility and release-process requirements are satisfied.
- Existing build warnings remain non-fatal, including some locale `msgfmt` warnings and libusb install permission warnings.
- The build script installs the pinned python.org macOS package with `sudo installer`.

## Rollback Notes

Rollback the implementation commit to remove the ARM64 build path.

Rollback the earlier documentation commits separately if needed:

- `0ed2e906f docs: clarify native macos arm64 build target`
- `f371c77ab docs: design experimental macos arm64 build`
- `efb39a49c docs: add contributor guide`
