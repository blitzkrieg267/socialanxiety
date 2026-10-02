#!/usr/bin/env bash
# =============================================================================
# bootstrap-vm.sh — one-time setup for an Oracle Cloud (Ubuntu) Always-Free VM.
#
# What it does:
#   1. Installs Docker Engine + the compose plugin.
#   2. Opens the local firewall for HTTP/HTTPS (the Oracle gotcha that blocks
#      almost everyone on their first deploy).
#   3. Generates an SSH "deploy key" so the VM can pull this PRIVATE repo and
#      so GitHub Actions can push deployments in.
#
# Run it once:  bash scripts/bootstrap-vm.sh
# (Re-running is safe — it is idempotent.)
# =============================================================================
set -euo pipefail

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

# -----------------------------------------------------------------------------
log "1/4  Installing Docker Engine + compose plugin"
# -----------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | $SUDO sh
  $SUDO usermod -aG docker "$USER" || true
  echo "Docker installed. (Log out/in once so your user can run docker without sudo.)"
else
  echo "Docker already present: $(docker --version)"
fi
$SUDO systemctl enable --now docker

# -----------------------------------------------------------------------------
log "2/4  Opening the local firewall for ports 80 and 443"
# -----------------------------------------------------------------------------
# Oracle's Ubuntu images ship an iptables INPUT chain that REJECTs everything
# except SSH. We prepend ACCEPT rules so web traffic gets in, then persist them.
# (You STILL must add ingress rules for 80/443 in the OCI console — see README.)
if command -v ufw >/dev/null 2>&1 && $SUDO ufw status | grep -q "Status: active"; then
  echo "ufw is active — allowing 80/443 via ufw."
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp
  $SUDO ufw reload
else
  echo "Configuring iptables directly."
  for proto_port in "tcp 80" "tcp 443" "udp 443"; do
    set -- $proto_port
    if ! $SUDO iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null; then
      $SUDO iptables -I INPUT -p "$1" --dport "$2" -j ACCEPT
    fi
  done
  # Persist across reboots.
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent netfilter-persistent
  $SUDO netfilter-persistent save
fi

# -----------------------------------------------------------------------------
log "3/4  Generating a GitHub deploy key (read access to this private repo)"
# -----------------------------------------------------------------------------
KEY=~/.ssh/socialanxiety_deploy
if [ ! -f "$KEY" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -N "" -C "socialanxiety-deploy@$(hostname)" -f "$KEY"
  # Make git use this key for github.com.
  cat >> ~/.ssh/config <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile $KEY
  IdentitiesOnly yes
EOF
  chmod 600 ~/.ssh/config
else
  echo "Deploy key already exists at $KEY"
fi

# -----------------------------------------------------------------------------
log "4/4  Done — next steps"
# -----------------------------------------------------------------------------
cat <<EOF

Add this PUBLIC key to the repo as a Deploy Key
  (GitHub -> repo Settings -> Deploy keys -> Add deploy key, 'Allow write access' OFF):

------------------------------------------------------------------------------
$(cat "${KEY}.pub")
------------------------------------------------------------------------------

Then clone and start the stack:

  git clone git@github.com:blitzkrieg267/socialanxiety.git ~/socialanxiety
  cd ~/socialanxiety
  cp .env.example .env
  nano .env          # fill in secrets + your domain
  docker compose up -d
  docker compose logs -f postiz

EOF
