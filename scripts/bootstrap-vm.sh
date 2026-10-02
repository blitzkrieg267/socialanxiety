#!/usr/bin/env bash
# =============================================================================
# bootstrap-vm.sh — one-time setup for an Ubuntu cloud VM (Azure, AWS, GCP, Oracle).
#
# What it does:
#   1. Installs Docker Engine + the compose plugin.
#   2. Opens the host firewall for HTTP/HTTPS ONLY if one is actually blocking
#      (Azure/AWS/GCP leave it open and gate at the cloud firewall; Oracle images
#      block locally — the script detects which and acts accordingly).
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
log "2/4  Host firewall (only touched if something is actually blocking)"
# -----------------------------------------------------------------------------
# Clouds differ: Azure/AWS/GCP leave the host firewall open and gate traffic at
# the cloud firewall (Azure NSG / AWS SG). Oracle's images instead ship an
# iptables INPUT chain that REJECTs everything but SSH. So: only act if ufw is
# active or iptables has a REJECT/DROP rule; otherwise leave the host alone.
if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
  echo "ufw is active — allowing 80/443 via ufw."
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp
  $SUDO ufw reload
elif $SUDO iptables -S INPUT 2>/dev/null | grep -qiE -- '-j (REJECT|DROP)'; then
  echo "Restrictive iptables rules detected (e.g. Oracle images) — opening 80/443."
  for proto_port in "tcp 80" "tcp 443" "udp 443"; do
    set -- $proto_port
    if ! $SUDO iptables -C INPUT -p "$1" --dport "$2" -j ACCEPT 2>/dev/null; then
      $SUDO iptables -I INPUT -p "$1" --dport "$2" -j ACCEPT
    fi
  done
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent netfilter-persistent
  $SUDO netfilter-persistent save
else
  echo "Host firewall is open (typical on Azure/AWS/GCP) — nothing to change here."
fi
echo
echo ">> REMINDER: also open 80 and 443 in your CLOUD firewall:"
echo "     Azure  -> VM 'Networking' blade: NSG inbound rules (TCP 80 + 443)"
echo "     AWS    -> the instance's Security Group inbound rules"
echo "     Oracle -> VCN Security List ingress rules"

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
