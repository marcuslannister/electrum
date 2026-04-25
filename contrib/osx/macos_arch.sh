#!/usr/bin/env bash

electrum_macos_get_arch() {
    local arch="${ELECTRUM_MACOS_ARCH:-x86_64}"
    case "$arch" in
        x86_64|arm64)
            printf '%s\n' "$arch"
            ;;
        *)
            echo "unsupported ELECTRUM_MACOS_ARCH '$arch'; expected x86_64 or arm64" >&2
            return 1
            ;;
    esac
}

electrum_macos_archflags() {
    local arch="$1"
    case "$arch" in
        x86_64|arm64)
            printf -- '-arch %s\n' "$arch"
            ;;
        *)
            echo "unsupported ELECTRUM_MACOS_ARCH '$arch'; expected x86_64 or arm64" >&2
            return 1
            ;;
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

electrum_macos_macho_info() {
    local path="$1"
    if command -v lipo > /dev/null 2>&1; then
        lipo -info "$path" 2>/dev/null && return 0
    fi
    file "$path" 2>/dev/null
}

electrum_macos_macho_has_arch() {
    local path="$1" arch="$2" info
    case "$arch" in
        x86_64|arm64) ;;
        *)
            echo "unsupported ELECTRUM_MACOS_ARCH '$arch'; expected x86_64 or arm64" >&2
            return 1
            ;;
    esac
    info="$(electrum_macos_macho_info "$path")" || return 1
    [[ "$info" == *"$arch"* ]]
}

electrum_macos_validate_macho_file() {
    local path="$1" arch="$2" info
    if electrum_macos_macho_has_arch "$path" "$arch"; then
        return 0
    fi
    info="$(electrum_macos_macho_info "$path" || true)"
    echo "$path does not contain architecture $arch: $info" >&2
    return 1
}

electrum_macos_check_host_arch() {
    local arch="$1" host_arch
    if [[ "$arch" != "arm64" ]]; then
        return 0
    fi
    host_arch="$(uname -m)"
    if [[ "$host_arch" != "arm64" ]]; then
        echo "host architecture '$host_arch' cannot build native arm64; run on Apple Silicon" >&2
        return 1
    fi
}

electrum_macos_check_python_runtime_arch() {
    local arch="$1" python_cmd="${2:-python3}" python_arch
    python_arch="$("$python_cmd" -c 'import platform; print(platform.machine())' 2>/dev/null)" || {
        echo "could not determine python runtime architecture using $python_cmd" >&2
        return 1
    }
    if [[ "$python_arch" != "$arch" ]]; then
        echo "$python_cmd runtime architecture '$python_arch' does not match expected '$arch'" >&2
        return 1
    fi
}

electrum_macos_check_clang_arch() {
    local arch="$1" tmpdir src out
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/electrum-macos-arch.XXXXXX")" || return 1
    src="$tmpdir/check.c"
    out="$tmpdir/check"
    echo 'int main(void) { return 0; }' > "$src"

    if ! clang -arch "$arch" "$src" -o "$out" >/dev/null 2>&1; then
        rm -rf "$tmpdir"
        echo "clang failed to build a $arch Mach-O executable" >&2
        return 1
    fi
    if ! electrum_macos_macho_has_arch "$out" "$arch"; then
        rm -rf "$tmpdir"
        echo "clang output does not contain architecture $arch" >&2
        return 1
    fi
    rm -rf "$tmpdir"
}

electrum_macos_find_bootloader() {
    local pyinstaller_dir="$1" arch="$2" candidate
    [[ -d "$pyinstaller_dir/PyInstaller/bootloader" ]] || return 1
    while IFS= read -r -d '' candidate; do
        if electrum_macos_macho_has_arch "$candidate" "$arch"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$pyinstaller_dir/PyInstaller/bootloader" -path '*/Darwin-*/runw' -type f -print0)
    return 1
}

electrum_macos_validate_app_bundle_arch() {
    local app_dir="$1" arch="$2" path info failed=0 found=0
    if [[ ! -d "$app_dir" ]]; then
        echo "app bundle not found: $app_dir" >&2
        return 1
    fi

    while IFS= read -r -d '' path; do
        info="$(file -b "$path" 2>/dev/null || true)"
        if [[ "$info" == *"Mach-O"* ]]; then
            found=1
            if ! electrum_macos_macho_has_arch "$path" "$arch"; then
                echo "$path does not contain architecture $arch: $info" >&2
                failed=1
            fi
        fi
    done < <(find "$app_dir" -type f -print0)

    if [[ "$found" -eq 0 ]]; then
        echo "no Mach-O files found in app bundle: $app_dir" >&2
        return 1
    fi

    return "$failed"
}
