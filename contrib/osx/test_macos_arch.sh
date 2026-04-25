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
    local output status
    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || fail "expected command to fail: $*"
    [[ "$output" == *"$expected"* ]] || fail "expected failure containing '$expected', got '$output'"
}

bad_arch() {
    ELECTRUM_MACOS_ARCH=universal2 electrum_macos_get_arch
}

assert_eq "x86_64" "$(electrum_macos_get_arch)"
assert_eq "arm64" "$(ELECTRUM_MACOS_ARCH=arm64 electrum_macos_get_arch)"
assert_fails "unsupported ELECTRUM_MACOS_ARCH" bad_arch

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

missing_arm64() {
    PATH="$tmpdir:$PATH" electrum_macos_validate_macho_file "$tmpdir/x86.bin" arm64
}

assert_fails "does not contain architecture arm64" missing_arm64

cat > "$tmpdir/python3" <<'EOF'
#!/usr/bin/env bash
echo arm64
EOF
chmod +x "$tmpdir/python3"

PATH="$tmpdir:$PATH" electrum_macos_check_python_runtime_arch arm64

cat > "$tmpdir/python-x86_64" <<'EOF'
#!/usr/bin/env bash
echo x86_64
EOF
chmod +x "$tmpdir/python-x86_64"

PATH="$tmpdir:$PATH" electrum_macos_check_python_runtime_arch x86_64 "$tmpdir/python-x86_64"

wrong_python_runtime() {
    PATH="$tmpdir:$PATH" electrum_macos_check_python_runtime_arch x86_64
}

assert_fails "python3 runtime architecture" wrong_python_runtime

grep -q 'target_arch=TARGET_ARCH' contrib/osx/pyinstaller.spec || fail "pyinstaller.spec must use TARGET_ARCH"
grep -q 'ELECTRUM_MACOS_ARCH' contrib/osx/pyinstaller.spec || fail "pyinstaller.spec must read ELECTRUM_MACOS_ARCH"
grep -q 'ELECTRUM_MACOS_ARCH' contrib/osx/make_osx.sh || fail "make_osx.sh must read ELECTRUM_MACOS_ARCH"
grep -q 'PIP_CERT=' contrib/osx/make_osx.sh || fail "make_osx.sh must set PIP_CERT for python.org macOS TLS"
grep -q 'LIBS=.*-liconv' contrib/make_zbar.sh || fail "make_zbar.sh must link libiconv on macOS"

echo "macOS arch tests passed"
