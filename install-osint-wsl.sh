#!/usr/bin/env bash
# install-osint-wsl.sh
# Idempotent WSL2 installer for Dale's OSINT forks under wilcox101-maker.
# Run inside Ubuntu (or similar) WSL:  bash install-osint-wsl.sh
# Optional: SKIP_PRYINGDEEP=1  SKIP_SOCIAL_NODE=1  INSTALL_ROOT=~/osint
set -euo pipefail

OWNER="${GITHUB_OWNER:-wilcox101-maker}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/osint}"
BIN_DIR="$INSTALL_ROOT/bin"
TOOLS_DIR="$INSTALL_ROOT/tools"
VENV_DIR="$INSTALL_ROOT/venvs"
LOG_DIR="$INSTALL_ROOT/logs"
SKIP_PRYINGDEEP="${SKIP_PRYINGDEEP:-0}"
SKIP_SOCIAL_NODE="${SKIP_SOCIAL_NODE:-0}"
# Prefer 3.12: Ubuntu 25.x ships 3.14, which breaks lxml / several OSINT deps.
PYTHON_PREFERRED="${PYTHON_PREFERRED:-3.12}"
PYTHON_MIN="3.10"
PYTHON_BIN=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[x]${NC} %s\n" "$*" >&2; exit 1; }

require_wsl() {
  if ! grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    warn "This does not look like WSL. Continuing anyway (Linux is fine)."
  else
    info "WSL detected."
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }

py_ver() {
  "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true
}

ensure_python() {
  local sys_ver pref="python${PYTHON_PREFERRED}"
  sys_ver="$(py_ver python3)"
  info "System python3 is ${sys_ver:-unknown}"

  # Use preferred 3.12 when available, or when system is 3.13+ (wheel gaps).
  local need_pref=0
  if [[ -n "$sys_ver" ]]; then
    local major minor
    major="${sys_ver%%.*}"
    minor="${sys_ver#*.}"
    if (( major > 3 || (major == 3 && minor >= 13) )); then
      need_pref=1
    fi
  fi

  if command -v "$pref" >/dev/null 2>&1; then
    PYTHON_BIN="$pref"
  elif (( need_pref )); then
    info "Installing Python ${PYTHON_PREFERRED} via deadsnakes (needed for OSINT deps on ${sys_ver})"
    apt_install software-properties-common
    if ! grep -qr deadsnakes /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
      sudo add-apt-repository -y ppa:deadsnakes/ppa
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
    fi
    apt_install "python${PYTHON_PREFERRED}" "python${PYTHON_PREFERRED}-venv" "python${PYTHON_PREFERRED}-dev" || \
      fail "Could not install python${PYTHON_PREFERRED}. Set PYTHON_PREFERRED=3.11 or install via pyenv."
    command -v "$pref" >/dev/null 2>&1 || fail "python${PYTHON_PREFERRED} still missing after apt install"
    PYTHON_BIN="$pref"
  else
    PYTHON_BIN="python3"
  fi

  local ver
  ver="$(py_ver "$PYTHON_BIN")"
  info "Using $PYTHON_BIN ($ver) for tool venvs"
  "$PYTHON_BIN" -c "import sys; raise SystemExit(0 if sys.version_info >= (${PYTHON_MIN%%.*}, ${PYTHON_MIN#*.}) else 1)" \
    || fail "Need Python >= ${PYTHON_MIN} (found ${ver})."
}

apt_install() {
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if ((${#missing[@]})); then
    info "Installing packages: ${missing[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  else
    info "System packages already present."
  fi
}

clone_or_update() {
  local repo="$1"
  local dest="$TOOLS_DIR/$repo"
  if [[ -d "$dest/.git" ]]; then
    info "Updating $repo"
    git -C "$dest" pull --ff-only || warn "Could not fast-forward $repo; leaving as-is."
  else
    info "Cloning $OWNER/$repo"
    git clone --depth 1 "https://github.com/${OWNER}/${repo}.git" "$dest"
  fi
}

make_venv() {
  local name="$1"
  local venv="$VENV_DIR/$name"
  local recreate=0
  if [[ -d "$venv" ]]; then
    local cur
    cur="$("$venv/bin/python" -c 'import sys; print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo missing)"
    local want
    want="$(py_ver "$PYTHON_BIN")"
    if [[ "$cur" != "$want" ]]; then
      warn "Recreating venv $name ($cur → $want)"
      recreate=1
    fi
  else
    recreate=1
  fi
  if (( recreate )); then
    rm -rf "$venv"
    info "Creating venv: $name with $PYTHON_BIN"
    "$PYTHON_BIN" -m venv "$venv"
  fi
  # shellcheck disable=SC1090
  source "$venv/bin/activate"
  python -m pip install --upgrade pip wheel setuptools >/dev/null
}

write_wrapper() {
  local name="$1"
  local body="$2"
  local path="$BIN_DIR/$name"
  cat > "$path" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
INSTALL_ROOT="${INSTALL_ROOT}"
TOOLS_DIR="${TOOLS_DIR}"
VENV_DIR="${VENV_DIR}"
${body}
WRAP
  chmod +x "$path"
}

# --- layout ---
require_wsl
mkdir -p "$BIN_DIR" "$TOOLS_DIR" "$VENV_DIR" "$LOG_DIR" "$INSTALL_ROOT/output"
need_cmd sudo
need_cmd git

info "Installing base system packages"
apt_install \
  git curl ca-certificates build-essential \
  python3 python3-venv python3-pip python3-dev \
  libxml2-dev libxslt1-dev libffi-dev libssl-dev \
  zlib1g-dev libjpeg-dev

ensure_python

# Node for social-analyzer (preferred path)
if [[ "$SKIP_SOCIAL_NODE" != "1" ]]; then
  info "Installing Node.js + Firefox ESR + tesseract (social-analyzer)"
  # Node from NodeSource LTS if node missing or too old
  if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | sed 's/v//;s/\..*//')" -lt 18 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    apt_install nodejs
  fi
  apt_install firefox-esr tesseract-ocr tesseract-ocr-eng || \
    apt_install firefox tesseract-ocr tesseract-ocr-eng || \
    warn "Firefox/tesseract install skipped — social-analyzer screenshots may be limited."
fi

# Optional Go for pryingdeep
if [[ "$SKIP_PRYINGDEEP" != "1" ]]; then
  if ! command -v go >/dev/null 2>&1; then
    info "Installing Go (for pryingdeep)"
    apt_install golang-go
  fi
fi

# ---------- blackbird ----------
clone_or_update blackbird
make_venv blackbird
pip install -r "$TOOLS_DIR/blackbird/requirements.txt"
deactivate
write_wrapper blackbird '
source "$VENV_DIR/blackbird/bin/activate"
cd "$TOOLS_DIR/blackbird"
exec python blackbird.py "$@"
'

# ---------- holehe ----------
clone_or_update holehe
make_venv holehe
pip install "$TOOLS_DIR/holehe"
# facebook (and others) import requests; not always declared in setup
pip install requests
deactivate
write_wrapper holehe '
source "$VENV_DIR/holehe/bin/activate"
exec holehe "$@"
'
write_wrapper holehe-used '
source "$VENV_DIR/holehe/bin/activate"
exec holehe --only-used --no-clear "$@"
'

# ---------- CrossLinked ----------
clone_or_update CrossLinked
make_venv crosslinked
pip install "$TOOLS_DIR/CrossLinked"
deactivate
write_wrapper crosslinked '
source "$VENV_DIR/crosslinked/bin/activate"
exec crosslinked "$@"
'
# Also expose the raw module name some docs use
write_wrapper CrossLinked '
source "$VENV_DIR/crosslinked/bin/activate"
if command -v crosslinked >/dev/null 2>&1; then
  exec crosslinked "$@"
fi
exec python "$TOOLS_DIR/CrossLinked/crosslinked.py" "$@"
'

# ---------- metagoofil (legacy; deps vendored) ----------
clone_or_update metagoofil
make_venv metagoofil
# Old tree ships its own libs; ensure requests/beautifulsoup for Google query bits if needed
pip install requests beautifulsoup4 lxml || true
deactivate
write_wrapper metagoofil '
source "$VENV_DIR/metagoofil/bin/activate"
cd "$TOOLS_DIR/metagoofil"
# Prefer python3; fall back if script is py2-only
if python -c "import ast; ast.parse(open(\"metagoofil.py\").read())" 2>/dev/null; then
  exec python metagoofil.py "$@"
fi
warn_py() { echo "metagoofil.py may need Python 2 syntax fixes on this tree." >&2; }
warn_py
exec python metagoofil.py "$@"
'

# ---------- spiderfoot ----------
clone_or_update spiderfoot
make_venv spiderfoot
pip install -r "$TOOLS_DIR/spiderfoot/requirements.txt"
deactivate
write_wrapper spiderfoot '
source "$VENV_DIR/spiderfoot/bin/activate"
cd "$TOOLS_DIR/spiderfoot"
# Bind localhost so Windows browser can open via WSL localhost forwarding
HOST="${SF_HOST:-127.0.0.1}"
PORT="${SF_PORT:-5001}"
if [[ "${1:-}" == "cli" ]]; then
  shift
  exec python ./sf.py "$@"
fi
echo "SpiderFoot UI → http://${HOST}:${PORT}  (open from Windows browser)"
exec python ./sf.py -l "${HOST}:${PORT}" "$@"
'
write_wrapper spiderfoot-cli '
source "$VENV_DIR/spiderfoot/bin/activate"
cd "$TOOLS_DIR/spiderfoot"
exec python ./sfcli.py "$@"
'

# ---------- social-analyzer ----------
clone_or_update social-analyzer
if [[ "$SKIP_SOCIAL_NODE" != "1" ]] && command -v npm >/dev/null 2>&1; then
  info "Installing social-analyzer (Node)"
  (
    cd "$TOOLS_DIR/social-analyzer"
    npm install --omit=dev
  )
  write_wrapper social-analyzer '
cd "$TOOLS_DIR/social-analyzer"
if [[ "${1:-}" == "web" ]]; then
  shift
  echo "Social Analyzer web → http://127.0.0.1:9005/app.html"
  exec npm start "$@"
fi
if [[ "${1:-}" == "--" ]]; then shift; fi
exec nodejs app.js "$@"
'
  write_wrapper social-analyzer-web '
cd "$TOOLS_DIR/social-analyzer"
echo "Social Analyzer web → http://127.0.0.1:9005/app.html"
exec npm start
'
else
  warn "Skipping Node social-analyzer; installing Python package instead."
  make_venv social-analyzer
  pip install social-analyzer
  deactivate
  write_wrapper social-analyzer '
source "$VENV_DIR/social-analyzer/bin/activate"
exec python -m social-analyzer "$@"
'
fi

# ---------- pryingdeep (optional / heavier) ----------
if [[ "$SKIP_PRYINGDEEP" != "1" ]]; then
  clone_or_update pryingdeep
  if command -v go >/dev/null 2>&1; then
    info "Building pryingdeep (Go). Needs Postgres + Tor for full dark-web use."
    (
      cd "$TOOLS_DIR/pryingdeep"
      if [[ -d cmd/pryingdeep ]]; then
        go build -o "$BIN_DIR/pryingdeep" ./cmd/pryingdeep
      else
        go build -o "$BIN_DIR/pryingdeep" ./cmd/pryingdeep/pryingdeep.go 2>/dev/null \
          || go install -v github.com/iudicium/pryingdeep/cmd/pryingdeep@latest \
          || warn "pryingdeep build failed — repo is unmaintained; use Docker if needed."
      fi
    )
    # Config bootstrap helper
    write_wrapper pryingdeep-setup '
set -euo pipefail
cd "$TOOLS_DIR/pryingdeep"
if [[ -x "$BIN_DIR/pryingdeep" ]]; then
  "$BIN_DIR/pryingdeep" install || true
elif command -v pryingdeep >/dev/null 2>&1; then
  pryingdeep install || true
fi
echo "Edit config under $TOOLS_DIR/pryingdeep (pryingdeep.yaml / config)."
echo "Full dark-web crawl needs Tor + Postgres — see the repo Docker docs."
echo "Upstream note: author marked the project inactive."
'
  else
    warn "Go not available; skipping pryingdeep build."
  fi
else
  warn "SKIP_PRYINGDEEP=1 — not installing pryingdeep."
fi

# ---------- PATH + shellrc ----------
MARKER="# osint-wsl-setup"
SHELL_RC=""
if [[ -f "$HOME/.bashrc" ]]; then SHELL_RC="$HOME/.bashrc"; fi
if [[ -n "${ZSH_VERSION:-}" ]] || [[ -f "$HOME/.zshrc" ]]; then
  # Prefer bashrc for WSL Ubuntu default; still append zsh if present
  :
fi
append_path() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0
  if ! grep -qF "$MARKER" "$rc" 2>/dev/null; then
    info "Adding $BIN_DIR to PATH in $rc"
    cat >> "$rc" <<PATHBLOCK

$MARKER
export OSINT_ROOT="$INSTALL_ROOT"
export PATH="$BIN_DIR:\$PATH"
PATHBLOCK
  fi
}
append_path "$HOME/.bashrc"
[[ -f "$HOME/.zshrc" ]] && append_path "$HOME/.zshrc"

# ---------- smoke checks (import / help only; no live targets) ----------
info "Smoke-checking wrappers (help / -h only)"
set +e
"$BIN_DIR/blackbird" --help >/dev/null 2>&1 && info "blackbird OK" || warn "blackbird help failed"
"$BIN_DIR/holehe" --help >/dev/null 2>&1 && info "holehe OK" || warn "holehe help failed"
"$BIN_DIR/crosslinked" -h >/dev/null 2>&1 && info "crosslinked OK" || warn "crosslinked help failed"
"$BIN_DIR/metagoofil" -h >/dev/null 2>&1 && info "metagoofil OK" || warn "metagoofil help failed (legacy tool)"
test -f "$TOOLS_DIR/spiderfoot/sf.py" && info "spiderfoot files OK" || warn "spiderfoot missing"
command -v node >/dev/null && test -d "$TOOLS_DIR/social-analyzer/node_modules" && info "social-analyzer (node) OK" \
  || test -x "$BIN_DIR/social-analyzer" && info "social-analyzer wrapper OK" \
  || warn "social-analyzer check inconclusive"
set -e

cat <<DONE

${GREEN}Done.${NC}
Install root:  $INSTALL_ROOT
Wrappers:      $BIN_DIR  (on PATH after: source ~/.bashrc)

Quick start (educational / authorized use only):
  blackbird --username example
  holehe example@example.com
  crosslinked -f '{first}.{last}@example.com' "Example Company"
  metagoofil -d example.com -t pdf -l 20 -o $INSTALL_ROOT/output -f results.html
  spiderfoot          # UI at http://127.0.0.1:5001 from Windows browser
  social-analyzer --username example
  social-analyzer web # UI at http://127.0.0.1:9005/app.html

Docs: $INSTALL_ROOT/README.md  (copy from the same folder as this script)

Re-run is safe. Skip heavy pieces with:
  SKIP_PRYINGDEEP=1 SKIP_SOCIAL_NODE=1 bash install-osint-wsl.sh
DONE
