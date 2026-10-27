# OSINT tools on WSL2 (wilcox101-maker forks)

> **Educational / authorized use only.** `install-osint-wsl.sh` clones and wraps third-party OSINT tools so you can learn them on a machine you control. Run them against accounts, domains, and networks you are allowed to investigate. Upstream projects keep their own licenses. This repository does not vendor those trees and does not ship API keys, scan output, or target lists.

The installer runs inside Ubuntu on WSL2 (other Debian-family Linux works, with a warning when `/proc/version` does not look like WSL). It clones these seven forks, builds one environment per tool, and drops wrappers on your `PATH`.

| Tool | Kind | Wrapper | What the installer sets up |
|------|------|---------|----------------------------|
| [blackbird](https://github.com/wilcox101-maker/blackbird) | Python CLI | `blackbird` | `pip install -r requirements.txt`, then `python blackbird.py` |
| [holehe](https://github.com/wilcox101-maker/holehe) | Python CLI | `holehe`, `holehe-used` | Installs the clone plus `requests`. `holehe-used` adds `--only-used --no-clear` |
| [CrossLinked](https://github.com/wilcox101-maker/CrossLinked) | Python CLI | `crosslinked`, `CrossLinked` | Installs the clone. `CrossLinked` falls back to `crosslinked.py` |
| [metagoofil](https://github.com/wilcox101-maker/metagoofil) | Python CLI | `metagoofil` | Legacy tree. Also installs `requests`, `beautifulsoup4`, and `lxml` when pip can |
| [spiderfoot](https://github.com/wilcox101-maker/spiderfoot) | Python UI/CLI | `spiderfoot`, `spiderfoot-cli` | UI listens on `127.0.0.1:5001` unless `SF_HOST` / `SF_PORT` override it |
| [social-analyzer](https://github.com/wilcox101-maker/social-analyzer) | Node, or Python if Node is skipped | `social-analyzer`, `social-analyzer-web` | Node path: `npm install --omit=dev`. `web` serves `http://127.0.0.1:9005/app.html` |
| [pryingdeep](https://github.com/wilcox101-maker/pryingdeep) | Go | `pryingdeep`, `pryingdeep-setup` | Optional. Upstream is inactive. Full use needs Postgres and Tor |

Default clone URL: `https://github.com/wilcox101-maker/<repo>`. Override the owner with `GITHUB_OWNER`.

## Prerequisites (Windows)

1. WSL2 with Ubuntu. 22.04 and 24.04 match the apt packages directly. 25.x works after the Python 3.12 step below. From an elevated PowerShell:

   ```powershell
   wsl --install -d Ubuntu
   ```

2. Inside Ubuntu, `sudo` and `git` must work. The script installs the rest.
3. Docker Desktop with the WSL integration is optional, and only for running pryingdeep from its own Compose file.

## Python 3.12 and deadsnakes

Several OSINT dependencies (notably `lxml`) do not ship wheels for very new CPython. The installer prefers **Python 3.12**:

- If `python3.12` is already on `PATH`, every virtualenv uses it.
- If it is missing and `python3` is **3.13 or newer** (Ubuntu 25.x ships 3.14), the script adds the [deadsnakes](https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa) PPA and installs `python3.12`, `python3.12-venv`, and `python3.12-dev`.
- Otherwise it uses system `python3`.

The interpreter must be **at least 3.10**. Point `PYTHON_PREFERRED` at another minor version when you want that instead (`PYTHON_PREFERRED=3.11`). If apt cannot install it, install that version yourself (or with pyenv) and re-run. A later run recreates any venv whose Python minor version does not match.

## Install

From Windows PowerShell, in this folder, `Copy-ToWsl.ps1` creates `~/osint-src` in the Ubuntu distro and copies `install-osint-wsl.sh` and `README.md` (it also marks the shell script executable):

```powershell
.\Copy-ToWsl.ps1
# other distro or folder:
.\Copy-ToWsl.ps1 -Distro Ubuntu -RemoteDir osint-src
```

The script checks that `install-osint-wsl.sh`, `README.md`, and `Copy-ToWsl.ps1` exist beside it. It does not copy `holehe-used`; the installer writes its own `holehe-used` wrapper under `~/osint/bin`. To keep this repo's standalone helper next to the installer:

```powershell
tar -cf - holehe-used | wsl -d Ubuntu -- bash -lc "cd ~/osint-src && tar -xf - && chmod +x holehe-used"
```

Or, if the files are already visible inside WSL:

```bash
cd ~/osint-src
bash install-osint-wsl.sh
source ~/.bashrc
```

The script is safe to re-run. Existing clones update with `git pull --ff-only` (a failed fast-forward is left as-is). Wrappers are rewritten each run.

Default layout (`INSTALL_ROOT`, normally `~/osint`):

```
~/osint/
  tools/     # shallow clones
  venvs/     # one virtualenv per Python tool
  bin/       # wrappers added to PATH
  output/    # suggested export directory
  logs/
```

`~/.bashrc` and, when the file exists, `~/.zshrc` gain a `# osint-wsl-setup` block that exports `OSINT_ROOT` and prepends `~/osint/bin`. The installer does not copy this README into `~/osint`. The finish message mentions `~/osint/README.md` as a place you can copy it:

```bash
cp ~/osint-src/README.md ~/osint/README.md
```

### Options

```bash
# Skip the Go crawler, and install social-analyzer from PyPI instead of Node
SKIP_PRYINGDEEP=1 SKIP_SOCIAL_NODE=1 bash install-osint-wsl.sh

# Custom install root and fork owner
INSTALL_ROOT=~/recon GITHUB_OWNER=wilcox101-maker bash install-osint-wsl.sh

# Prefer a different CPython when 3.12 is wrong for this machine
PYTHON_PREFERRED=3.11 bash install-osint-wsl.sh
```

| Variable | Default | Effect |
|----------|---------|--------|
| `INSTALL_ROOT` | `~/osint` | Tools, venvs, wrappers, logs, output |
| `GITHUB_OWNER` | `wilcox101-maker` | GitHub user or org cloned for each tool |
| `SKIP_PRYINGDEEP` | `0` | `1` skips Go and the pryingdeep clone |
| `SKIP_SOCIAL_NODE` | `0` | `1` skips Node, Firefox, and tesseract, and uses `pip install social-analyzer` |
| `PYTHON_PREFERRED` | `3.12` | Binary name `python3.12` (or whatever minor you set) |
| `SF_HOST` | `127.0.0.1` | SpiderFoot UI bind address (read by the wrapper) |
| `SF_PORT` | `5001` | SpiderFoot UI port |

When Node is not skipped, missing Node or a major version below 18 triggers NodeSource's Node.js 20 setup. Firefox ESR and English tesseract data are installed for social-analyzer screenshots; if `firefox-esr` is unavailable the script tries `firefox`, then continues with a warning.

The last step runs `--help` / `-h` smoke checks only. It does not query live targets.

## Run examples

Use addresses and names you are authorized to look up. These match the installer's quick-start flags. Pass `--help` or `-h` for the full upstream interface.

```bash
blackbird --username example
holehe user@example.com
holehe-used user@example.com

crosslinked -f '{first}.{last}@example.com' "Example Company"

metagoofil -d example.com -t pdf -l 20 -o ~/osint/output -f results.html

# Leave this running. Open http://127.0.0.1:5001 in a Windows browser.
spiderfoot
spiderfoot cli -h
spiderfoot-cli -h

social-analyzer --username example
social-analyzer web
# Node install: http://127.0.0.1:9005/app.html
```

`holehe-used` in this repository is a small standalone script. It execs `$HOME/osint/bin/holehe` (or `$HOLEHE_BIN`, then the holehe venv binary) with `--only-used --no-clear`. After install, `~/osint/bin/holehe-used` does the same thing from `PATH`.

WSL2 forwards those localhost ports to Windows, so the SpiderFoot and social-analyzer URLs open in Chrome or Edge without extra portproxy rules. With `SKIP_SOCIAL_NODE=1`, `social-analyzer` is `python -m social-analyzer` and the `:9005` web UI is not installed.

## pryingdeep (optional)

Upstream marked the project inactive. The installer still tries a local build when `go` is available:

1. `go build -o ~/osint/bin/pryingdeep ./cmd/pryingdeep`
2. Otherwise `./cmd/pryingdeep/pryingdeep.go`
3. Otherwise `go install` of `github.com/iudicium/pryingdeep/cmd/pryingdeep@latest`

`golang-go` is installed from apt when `go` is missing. A failed build is a warning, not a failed install.

```bash
pryingdeep-setup
# runs `pryingdeep install` when the binary exists, then points you at
# pryingdeep.yaml / config under ~/osint/tools/pryingdeep
```

Dark-web crawling needs Tor and PostgreSQL. The wrapper prints that requirement. The Compose file in the clone is the shorter path when Docker is already wired to WSL:

```bash
cd ~/osint/tools/pryingdeep
docker compose up
```

Skip the tool with `SKIP_PRYINGDEEP=1`.

## Updating

```bash
bash ~/osint-src/install-osint-wsl.sh
```

Or one Python tool at a time:

```bash
git -C ~/osint/tools/blackbird pull --ff-only
source ~/osint/venvs/blackbird/bin/activate
pip install -r ~/osint/tools/blackbird/requirements.txt
```

## Uninstall

```bash
rm -rf ~/osint
```

Remove the `# osint-wsl-setup` block from `~/.bashrc` and from `~/.zshrc` if you use zsh. Remove `~/osint-src` when you no longer want the installer copy.

## Troubleshooting

| Symptom | What to do |
|---------|------------|
| `command not found` after install | `source ~/.bashrc`, or open a new WSL tab so the PATH block loads |
| Not WSL | The script warns and continues. Apt package names assume Debian/Ubuntu |
| `sudo` or `git` missing | Install them first. Both are required before clones start |
| deadsnakes / `python3.12` install fails | Install that Python yourself and re-run, or set `PYTHON_PREFERRED` to a version already on `PATH`. Need `>= 3.10` |
| `pip` or TLS errors | `sudo apt-get install -y ca-certificates` and re-run |
| SpiderFoot or social-analyzer URL fails in Windows | Confirm the process is listening: `ss -ltn \| grep -E '5001\|9005'`. Use `http://127.0.0.1` rather than the WSL eth0 address |
| social-analyzer screenshots empty | Firefox and tesseract are installed on the Node path. `SKIP_SOCIAL_NODE=1` skips both |
| social-analyzer `web` does nothing useful | That subcommand exists on the Node wrapper. The PyPI fallback is CLI-only |
| metagoofil errors on Python 3 | The tree is legacy. The wrapper still launches `metagoofil.py` and prints a warning when the file does not parse |
| holehe import errors for `requests` | Re-run the installer. It installs `requests` into the holehe venv because the package metadata does not always declare it |
| `git pull --ff-only` warning | Local edits diverged. Fix that clone by hand or delete `~/osint/tools/<name>` and re-run |
| GitHub clone rate limit | Authenticate git (`gh auth login` and `gh auth setup-git`) or wait and re-run |
| pryingdeep build warning | Expected on the unmaintained layout. Use the repo's Docker docs, or skip with `SKIP_PRYINGDEEP=1` |

## Files in this repository

| File | Role |
|------|------|
| `install-osint-wsl.sh` | Idempotent installer. Run it inside WSL |
| `Copy-ToWsl.ps1` | Copies the installer and this README into Ubuntu |
| `holehe-used` | Standalone wrapper around an already installed `holehe` |
| `LICENSE` | MIT, Copyright 2026 Dale Wilcox |

Clones, virtualenvs, and scan output stay under `INSTALL_ROOT` on the machine that ran the installer. Do not commit them back here.
