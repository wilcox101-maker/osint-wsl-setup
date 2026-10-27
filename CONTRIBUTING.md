# Contributing

This repository holds the WSL2 installer and its docs. Tool source lives in the [wilcox101-maker](https://github.com/wilcox101-maker) forks that `install-osint-wsl.sh` clones at runtime.

## Authorized use

Use the installer and the tools it sets up for education, your own accounts, or investigations you are allowed to run. Issues, pull requests, and commit messages should use placeholders such as `user@example.com`. Leave out real targets, scan exports, cookies, session tokens, and API keys.

## What to change here

- `install-osint-wsl.sh` and the small helpers (`holehe-used`, `Copy-ToWsl.ps1`)
- `README.md` and this file

Keep the README aligned with the script: environment variables, wrapper names, ports, and the quick-start commands are part of the installer contract. If a flag is only documented upstream, point readers at `--help` instead of inventing an example.

## What to leave out

Do not commit:

- Cloned OSINT trees (`tools/`, upstream checkouts, submodules of those projects)
- Virtualenvs, `node_modules`, or Go build caches
- `output/`, `logs/`, or other scan results
- `.env` files, keys, tokens, or private config

`.gitignore` already excludes that layout. Do not force-add it.

## How to send a change

1. Branch from `main`.
2. Keep `install-osint-wsl.sh` and `holehe-used` executable, with LF line endings and `set -euo pipefail`.
3. Run `bash -n` on both shell scripts. Run `shellcheck` on them when it is installed.
4. Open a pull request that describes the behavior change.

Re-runs must stay idempotent: update clones with `git pull --ff-only`, and refresh wrappers without deleting unrelated files under `INSTALL_ROOT`.

## License

Contributions are released under the MIT license in `LICENSE` (Copyright 2026 Dale Wilcox).
