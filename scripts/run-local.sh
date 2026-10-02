#!/usr/bin/env bash
# =============================================================================
# run-local.sh — launch Postiz on YOUR machine at http://localhost:4007
#
# Works on macOS, Linux, and Windows via Git Bash or WSL.
# It checks Docker, warns on low RAM, creates a local .env with generated
# secrets, and starts the stack (without the Caddy proxy).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# 1. Docker present and running? -----------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. Install Docker Desktop first:"
  echo "  https://www.docker.com/products/docker-desktop/"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running. Start Docker Desktop, then re-run this."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "Your Docker is too old (no 'docker compose'). Update Docker Desktop."
  exit 1
fi

# 2. RAM check (best effort) ---------------------------------------------------
ram_gb() {
  if [ "$(uname)" = "Darwin" ]; then
    echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
  elif [ -r /proc/meminfo ]; then
    echo $(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1048576 ))
  else
    echo 0
  fi
}
RAM=$(ram_gb)
if [ "$RAM" -gt 0 ]; then
  say "Detected ~${RAM} GB RAM on this machine."
  if [ "$RAM" -lt 8 ]; then
    echo "WARNING: under 8 GB RAM. Elasticsearch + the rest of the stack may swap"
    echo "or get OOM-killed. 8 GB is the practical minimum; 16 GB is comfortable."
    printf "Continue anyway? [y/N] "
    read -r ans
    case "$ans" in y|Y) ;; *) echo "Aborted."; exit 1 ;; esac
  fi
fi

# 3. Create local .env with generated secrets ---------------------------------
gen() { openssl rand -hex "$1" 2>/dev/null || head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }
if [ ! -f .env ]; then
  say "Creating local .env with generated secrets"
  cp .env.local.example .env
  JWT=$(gen 32)
  PW=$(gen 24)
  # Portable in-place edit (GNU & BSD sed).
  sed -i.bak -e "s|__JWT__|${JWT}|g" -e "s|__PW__|${PW}|g" .env
  rm -f .env.bak
  echo "Wrote .env (JWT_SECRET + POSTGRES_PASSWORD generated)."
else
  echo ".env already exists — leaving it as-is."
fi

# 4. Launch (no Caddy locally) -------------------------------------------------
FILES=(-f docker-compose.yaml -f docker-compose.local.yaml)
say "Pulling images — first run downloads roughly 5-6 GB, grab a coffee"
docker compose "${FILES[@]}" pull
say "Starting Postiz"
docker compose "${FILES[@]}" up -d

cat <<'EOF'

------------------------------------------------------------------------------
Postiz is starting. First boot runs database migrations (~2 minutes).

  Watch it come up:  docker compose -f docker-compose.yaml -f docker-compose.local.yaml logs -f postiz
  Then open:         http://localhost:4007

  Stop it:           docker compose -f docker-compose.yaml -f docker-compose.local.yaml down
  Start again:       bash scripts/run-local.sh
------------------------------------------------------------------------------
EOF
