# macOS ARM64 Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an experimental native Apple Silicon build path for the macOS Electrum `.app` while preserving the existing `x86_64` release default.

**Architecture:** Add one architecture selector, `ELECTRUM_MACOS_ARCH=x86_64|arm64`, and thread it through the shell build script and PyInstaller spec. Keep the default `x86_64` path close to current behavior, while using separate ARM64 cache directories and post-build Mach-O validation to prevent stale `x86_64` artifacts in ARM builds.

**Tech Stack:** Bash, PyInstaller spec Python, macOS command-line tools (`clang`, `file`, `lipo`), existing Electrum pytest suite.

---

## File Structure

- Create `contrib/osx/macos_arch.sh`: pure Bash helpers for arch validation, arch-specific paths, host/toolchain checks, bootloader discovery, and app bundle Mach-O validation.
- Create `contrib/osx/test_macos_arch.sh`: fast shell tests for helper behavior and static integration points.
- Modify `contrib/osx/make_osx.sh`: source helper, derive selected arch, use arch-specific caches, pass the arch into PyInstaller, and validate final app bundle.
- Modify `contrib/osx/pyinstaller.spec`: read and validate `ELECTRUM_MACOS_ARCH`, then pass it to `EXE(... target_arch=...)`.
- Modify `contrib/osx/README.md`: document default `x86_64` release behavior and experimental ARM64 local build command.

## Task 1: Add Failing Fast Tests

**Files:**
- Create: `contrib/osx/test_macos_arch.sh`
- Not yet created: `contrib/osx/macos_arch.sh`

- [ ] **Step 1: Write the failing shell test**

Create `contrib/osx/test_macos_arch.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

source contrib/osx/macos_arch.sh

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2"
    [[ "$actual" == "$expected" ]] || fail "expected '$expected', got '$actual'"
}

assert_fails() {
    local expected="$1"
    shift
    local output
    if output="$("$@" 2>&1)"; then
        fail "expected command to fail: $*"
    fi
    [[ "$output" == *"$expected"* ]] || fail "expected failure containing '$expected', got '$output'"
}

assert_eq "x86_64" "$(electrum_macos_get_arch)"
assert_eq "arm64" "$(ELECTRUM_MACOS_ARCH=arm64 electrum_macos_get_arch)"
assert_fails "unsupported ELECTRUM_MACOS_ARCH" env ELECTRUM_MACOS_ARCH=universal2 electrum_macos_get_arch

assert_eq "-arch x86_64" "$(electrum_macos_archflags x86_64)"
assert_eq "-arch arm64" "$(electrum_macos_archflags arm64)"

assert_eq "/tmp/electrum-cache/dlls" "$(electrum_macos_cache_subdir /tmp/electrum-cache dlls x86_64)"
assert_eq "/tmp/electrum-cache/dlls-arm64" "$(electrum_macos_cache_subdir /tmp/electrum-cache dlls arm64)"
assert_eq "/tmp/electrum-cache/pip_cache" "$(electrum_macos_cache_subdir /tmp/electrum-cache pip_cache x86_64)"
assert_eq "/tmp/electrum-cache/pip_cache-arm64" "$(electrum_macos_cache_subdir /tmp/electrum-cache pip_cache arm64)"

assert_eq "dist/electrum-4.5.8-unsigned.dmg" "$(electrum_macos_unsigned_dmg_path dist 4.5.8 x86_64)"
assert_eq "dist/electrum-4.5.8-arm64-unsigned.dmg" "$(electrum_macos_unsigned_dmg_path dist 4.5.8 arm64)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/lipo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" != "-info" ]]; then
    exit 2
fi
case "$2" in
    *universal*) echo "Architectures in the fat file: $2 are: x86_64 arm64" ;;
    *arm64*) echo "Non-fat file: $2 is architecture: arm64" ;;
    *x86*) echo "Non-fat file: $2 is architecture: x86_64" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmpdir/lipo"

PATH="$tmpdir:$PATH" electrum_macos_macho_has_arch "$tmpdir/universal.bin" arm64
PATH="$tmpdir:$PATH" electrum_macos_macho_has_arch "$tmpdir/x86.bin" x86_64
assert_fails "does not contain architecture arm64" env PATH="$tmpdir:$PATH" electrum_macos_validate_macho_file "$tmpdir/x86.bin" arm64

cat > "$tmpdir/python3" <<'EOF'
#!/usr/bin/env bash
echo arm64
EOF
chmod +x "$tmpdir/python3"
PATH="$tmpdir:$PATH" electrum_macos_check_python_runtime_arch arm64
assert_fails "python3 runtime architecture" env PATH="$tmpdir:$PATH" electrum_macos_check_python_runtime_arch x86_64

grep -q 'target_arch=TARGET_ARCH' contrib/osx/pyinstaller.spec || fail "pyinstaller.spec must use TARGET_ARCH"
grep -q 'ELECTRUM_MACOS_ARCH' contrib/osx/pyinstaller.spec || fail "pyinstaller.spec must read ELECTRUM_MACOS_ARCH"
grep -q 'ELECTRUM_MACOS_ARCH' contrib/osx/make_osx.sh || fail "make_osx.sh must read ELECTRUM_MACOS_ARCH"

echo "macOS arch tests passed"
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash contrib/osx/test_macos_arch.sh
```

Expected: FAIL because `contrib/osx/macos_arch.sh` does not exist yet.

## Task 2: Implement Architecture Helper

**Files:**
- Create: `contrib/osx/macos_arch.sh`
- Test: `contrib/osx/test_macos_arch.sh`

- [ ] **Step 1: Add helper implementation**

Create `contrib/osx/macos_arch.sh` with pure functions:

```bash
#!/usr/bin/env bash

electrum_macos_get_arch() {
    local arch="${ELECTRUM_MACOS_ARCH:-x86_64}"
    case "$arch" in
        x86_64|arm64) printf '%s\n' "$arch" ;;
        *) echo "unsupported ELECTRUM_MACOS_ARCH '$arch'; expected x86_64 or arm64" >&2; return 1 ;;
    esac
}

electrum_macos_archflags() {
    local arch="$1"
    case "$arch" in
        x86_64|arm64) printf -- '-arch %s\n' "$arch" ;;
        *) echo "unsupported ELECTRUM_MACOS_ARCH '$arch'; expected x86_64 or arm64" >&2; return 1 ;;
    esac
}

electrum_macos_cache_subdir() {
    local base="$1" name="$2" arch="$3"
    if [[ "$arch" == "x86_64" ]]; then
        printf '%s/%s\n' "$base" "$name"
    else
        printf '%s/%s-%s\n' "$base" "$name" "$arch"
    fi
}

electrum_macos_unsigned_dmg_path() {
    local dist_dir="$1" version="$2" arch="$3"
    if [[ "$arch" == "x86_64" ]]; then
        printf '%s/electrum-%s-unsigned.dmg\n' "$dist_dir" "$version"
    else
        printf '%s/electrum-%s-%s-unsigned.dmg\n' "$dist_dir" "$version" "$arch"
    fi
}
```

Also add helpers for `lipo`/`file` validation, Python runtime checks, clang checks, bootloader discovery, and app bundle validation. The validation failure must name the file and expected architecture.

- [ ] **Step 2: Run the helper test and verify GREEN**

Run:

```bash
bash contrib/osx/test_macos_arch.sh
```

Expected: PASS and print `macOS arch tests passed`.

## Task 3: Wire Architecture Through macOS Build Script

**Files:**
- Modify: `contrib/osx/make_osx.sh`
- Test: `contrib/osx/test_macos_arch.sh`

- [ ] **Step 1: Source helper and derive selected arch**

Add after `build_tools_util.sh` is sourced:

```bash
. "$(dirname "$0")/macos_arch.sh"

export ELECTRUM_MACOS_ARCH="$(electrum_macos_get_arch)"
```

- [ ] **Step 2: Use arch-specific caches**

Replace shared cache assignments with:

```bash
export DLL_TARGET_DIR="$(electrum_macos_cache_subdir "$CACHEDIR" dlls "$ELECTRUM_MACOS_ARCH")"
PIP_CACHE_DIR="$(electrum_macos_cache_subdir "$CACHEDIR" pip_cache "$ELECTRUM_MACOS_ARCH")"
PYINSTALLER_BUILD_DIR="$(electrum_macos_cache_subdir "$CACHEDIR" pyinstaller "$ELECTRUM_MACOS_ARCH")"
```

This preserves `.cache/dlls`, `.cache/pip_cache`, and `.cache/pyinstaller` for default `x86_64`, while using `*-arm64` paths for ARM64.

- [ ] **Step 3: Set the selected `ARCHFLAGS`**

Replace:

```bash
export ARCHFLAGS="-arch x86_64"
```

with:

```bash
export ARCHFLAGS="$(electrum_macos_archflags "$ELECTRUM_MACOS_ARCH")"
```

- [ ] **Step 4: Validate runtime, toolchain, and bootloader**

After the pinned Python version check, add:

```bash
electrum_macos_check_python_runtime_arch "$ELECTRUM_MACOS_ARCH" || fail "python3 runtime architecture is not $ELECTRUM_MACOS_ARCH"
electrum_macos_check_clang_arch "$ELECTRUM_MACOS_ARCH" || fail "clang cannot build $ELECTRUM_MACOS_ARCH Mach-O files"
```

Build PyInstaller inside `$PYINSTALLER_BUILD_DIR`, then check:

```bash
PYINSTALLER_BOOTLOADER="$(electrum_macos_find_bootloader "$PYINSTALLER_BUILD_DIR" "$ELECTRUM_MACOS_ARCH")" \
    || fail "Could not find PyInstaller runw bootloader for $ELECTRUM_MACOS_ARCH"
info "Using PyInstaller bootloader $PYINSTALLER_BOOTLOADER"
```

- [ ] **Step 5: Pass arch to PyInstaller and validate the final app**

Run PyInstaller with:

```bash
ELECTRUM_VERSION=$VERSION ELECTRUM_MACOS_ARCH=$ELECTRUM_MACOS_ARCH pyinstaller --noconfirm --clean contrib/osx/pyinstaller.spec
```

After the hash output, add:

```bash
electrum_macos_validate_app_bundle_arch "dist/${PACKAGE}.app" "$ELECTRUM_MACOS_ARCH" \
    || fail "Built app contains Mach-O files without $ELECTRUM_MACOS_ARCH"
```

Create the unsigned DMG with:

```bash
UNSIGNED_DMG="$(electrum_macos_unsigned_dmg_path dist "$VERSION" "$ELECTRUM_MACOS_ARCH")"
hdiutil create -fs HFS+ -volname "$PACKAGE" -srcfolder "dist/$PACKAGE.app" "$UNSIGNED_DMG"
```

- [ ] **Step 6: Run fast shell tests**

Run:

```bash
bash contrib/osx/test_macos_arch.sh
```

Expected: PASS.

## Task 4: Update PyInstaller Spec

**Files:**
- Modify: `contrib/osx/pyinstaller.spec`
- Test: `contrib/osx/test_macos_arch.sh`

- [ ] **Step 1: Add target arch env validation**

Add near the version validation:

```python
TARGET_ARCH = os.environ.get("ELECTRUM_MACOS_ARCH", "x86_64")
if TARGET_ARCH not in {"x86_64", "arm64"}:
    raise Exception(f"unsupported ELECTRUM_MACOS_ARCH: {TARGET_ARCH}")
```

- [ ] **Step 2: Use `TARGET_ARCH` in `EXE`**

Replace:

```python
target_arch='x86_64',
```

with:

```python
target_arch=TARGET_ARCH,
```

- [ ] **Step 3: Run fast shell tests**

Run:

```bash
bash contrib/osx/test_macos_arch.sh
```

Expected: PASS.

## Task 5: Update macOS Build Docs

**Files:**
- Modify: `contrib/osx/README.md`

- [ ] **Step 1: Document default and experimental ARM64 command**

Update the build section to state:

```markdown
By default, `./contrib/osx/make_osx.sh` builds the existing `x86_64`
release-style binary.

For experimental native Apple Silicon testing on an M-series Mac:

    ELECTRUM_MACOS_ARCH=arm64 ./contrib/osx/make_osx.sh

The ARM64 path is intended for direct local Apple Silicon builds. It is not
currently an official reproducible release path, and it does not change signing
or notarization behavior.
```

- [ ] **Step 2: Document ARM64 artifact validation**

Add:

```markdown
The ARM64 build uses ARM Python, an ARM-capable clang/SDK, and ARM-compatible
bundled native libraries. The build validates Mach-O files in the final app
bundle and fails if required files are `x86_64`-only.
```

## Task 6: Verification and ARM64 Build Attempt

**Files:**
- Validate all changed files.

- [ ] **Step 1: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output and exit 0.

- [ ] **Step 2: Run fast macOS arch tests**

Run:

```bash
bash contrib/osx/test_macos_arch.sh
```

Expected: `macOS arch tests passed`.

- [ ] **Step 3: Run Python suite**

Run:

```bash
env HOME=/tmp/electrum-pytest-home .venv/bin/python -m pytest tests -v
```

Expected: all tests pass, matching the current baseline of `945 passed, 6 skipped, 242 subtests passed`.

- [ ] **Step 4: Attempt native ARM64 app build**

Run only with user-approved escalation if needed, because this can download packages, invoke Homebrew, and use `sudo installer`:

```bash
ELECTRUM_MACOS_ARCH=arm64 ./contrib/osx/make_osx.sh
```

Expected success output includes an unsigned app and ARM64-named DMG:

```text
Finished building unsigned dist/Electrum.app
Creating unsigned .DMG
App was built successfully but was not code signed.
```

Expected ARM64 output path:

```text
dist/electrum-<version>-arm64-unsigned.dmg
```

If the build cannot complete because of sandboxing, missing sudo credentials, network downloads, Homebrew installation, or upstream dependency incompatibility, record the exact blocker and keep the fast shell tests plus Python suite as verified.

## Self-Review

- Spec coverage: the plan implements the arch selector, default `x86_64`, ARM64 toolchain/runtime validation, arch-specific caches, PyInstaller target arch, app Mach-O validation, README updates, and an ARM64 build attempt.
- Placeholder scan: no `TBD`, `TODO`, or unresolved task content remains.
- Type and name consistency: helper names used by the tests match helper names wired into `make_osx.sh`.
