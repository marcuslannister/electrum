# Repository Guidelines

## Project Structure & Module Organization

Electrum is a Python Bitcoin wallet. Core code lives in `electrum/`, with GUI code under `electrum/gui/`, plugins under `electrum/plugins/`, Lightning code under `electrum/ln*`, and packaged assets in the same tree. Tests live in `tests/`, including unit, QML, plugin, regtest, and wallet-upgrade fixtures. Build, dependency, and platform scripts live in `contrib/`; macOS packaging is in `contrib/osx/`, Linux in `contrib/build-linux/`, Windows in `contrib/build-wine/`, and Android in `contrib/android/`.

## Build, Test, and Development Commands

- `git submodule update --init`: initialize required submodules after cloning.
- `brew install autoconf automake libtool coreutils`: install macOS build tools needed for `electrum-ecc` source builds.
- `python3 -m pip install --user -e ".[gui,crypto]"`: install editable mode with Qt GUI and crypto dependencies.
- `python3 -m pip install --user -e ".[tests]"`: install test dependencies.
- `./run_electrum`: run Electrum from the checkout.
- `pytest tests -v`: run the full pytest suite.
- `pytest tests/test_bitcoin.py -v`: run one test module while iterating.
- `./contrib/osx/make_osx.sh`: build an unsigned macOS app and DMG; see `contrib/osx/README.md` first.

## Coding Style & Naming Conventions

Use Python 3.10+ and follow nearby code. Python files use 4-space indentation and descriptive `snake_case` names. Keep imports grouped by standard library, third-party, then local modules. Shell scripts should use `#!/usr/bin/env bash` and fail fast where practical. Preserve stable file names and entry points such as `run_electrum`, `setup.py`, and platform build scripts.

## Testing Guidelines

Use pytest for automated tests. Name new tests `tests/test_*.py` or place them beside the relevant plugin/QML suite. Add or update the nearest focused test when changing wallet logic, transaction handling, Lightning behavior, storage upgrades, or command output. For old-wallet changes, add fixtures under the existing `tests/test_storage_upgrade/` pattern. Run the narrow test first, then `pytest tests -v` when practical.

## Commit & Pull Request Guidelines

Recent history uses short, imperative subjects, often scoped with prefixes such as `qt:`, `build:`, `trampoline:`, or `test_lnrouter:`. Keep commits focused on one concern. Pull requests should include a summary, affected platforms or components, verification commands, linked issues, and screenshots or recordings for visible GUI changes.

## Security & Configuration Tips

Do not commit private keys, wallet files, secrets, local caches, build artifacts, or generated runtime databases. Be careful with changes touching signing, seed handling, transaction creation, networking, dependency pinning, or deterministic build scripts. Search call sites with `rg` before removing or renaming public symbols.
