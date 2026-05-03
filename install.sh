#!/bin/bash
# ==============================================================================
# Headscale + Headplane — Ubuntu 24.04 Standalone Installer (v2)
# Usage: bash install.sh [--domain head.example.com] [--ui-domain headscale.example.com]
#        [--admin-pass yourpassword] [--headscale-version 0.28.0]
#        [--headplane-tag v0.6.2] [--no-ssl] [--ssl]
# ==============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ── Log file (everything is tee'd here) ───────────────────────────────────────
LOG_FILE="/var/log/headscale-install.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Install started: $(date) ==="

# ── Print helpers ─────────────────────────────────────────────────────────────
banner() {
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
    printf "${BOLD}${BLUE}  %s${NC}\n" "$*"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
}
step()    { echo -e "\n${BOLD}${CYAN}[Step $1/4]  $2${NC}"; }
ok()      { echo -e "  ${GREEN}✔${NC}  $*"; }
info()    { echo -e "  ${BLUE}ℹ${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠  WARNING:${NC} $*" >&2; }
fail()    {
    echo -e "\n${RED}${BOLD}✖  ERROR: $*${NC}" >&2
    echo -e "${DIM}  Full log: ${LOG_FILE}${NC}" >&2
    exit 1
}

# ── Abort handler (prints context on unexpected exit) ─────────────────────────
_on_error() {
    local code=$? line=$1
    echo -e "\n${RED}${BOLD}✖  Installation aborted (exit $code at line $line).${NC}" >&2
    echo -e "${DIM}  Supervisor processes left in place for debugging.${NC}" >&2
    echo -e "${DIM}  Full log: ${LOG_FILE}${NC}" >&2
}
trap '_on_error $LINENO' ERR

# ── Retry wrapper: retry <attempts> <delay_s> <cmd…> ─────────────────────────
retry() {
    local attempts=$1 delay=$2; shift 2
    local n=1
    until "$@"; do
        if (( n >= attempts )); then
            warn "Command failed after $attempts attempts: $*"
            return 1
        fi
        warn "Attempt $n/$attempts failed — retrying in ${delay}s…"
        sleep "$delay"; (( n++ ))
    done
}

# ── Wait for a TCP port to open ───────────────────────────────────────────────
wait_port() {
    local label=$1 port=$2 timeout=${3:-30}
    local i=0
    printf "  Waiting for %s on port %s" "$label" "$port"
    until ss -tlnp 2>/dev/null | grep -q ":${port}[[:space:]]"; do
        if (( i >= timeout )); then
            echo
            fail "$label did not bind to port $port within ${timeout}s."
        fi
        printf "."; sleep 1; (( i++ ))
    done
    echo
    ok "$label is up on port $port"
}

# ── Defaults ──────────────────────────────────────────────────────────────────
DOMAIN="${DOMAIN:-headscale.visiosoft.com.tr}"
UI_DOMAIN="${UI_DOMAIN:-head.visiosoft.com.tr}"
ADMIN_PASS="${ADMIN_PASS:-}"
HEADSCALE_VERSION="${HEADSCALE_VERSION:-0.28.0}"
HEADPLANE_TAG="${HEADPLANE_TAG:-v0.6.2}"
INSTALL_SSL="${INSTALL_SSL:-}"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)            DOMAIN="$2";            shift 2 ;;
        --ui-domain)         UI_DOMAIN="$2";         shift 2 ;;
        --admin-pass)        ADMIN_PASS="$2";        shift 2 ;;
        --headscale-version) HEADSCALE_VERSION="$2"; shift 2 ;;
        --headplane-tag)     HEADPLANE_TAG="$2";     shift 2 ;;
        --no-ssl)            INSTALL_SSL="n";        shift   ;;
        --ssl)               INSTALL_SSL="y";        shift   ;;
        *) fail "Unknown option: $1" ;;
    esac
done

if [[ -z "$INSTALL_SSL" ]]; then
    read -rp "Install SSL Certificate (Let's Encrypt)? (y/n): " INSTALL_SSL
fi

if [[ -z "$ADMIN_PASS" ]]; then
    ADMIN_PASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20 || true)
    warn "No --admin-pass provided. Generated: ${BOLD}${ADMIN_PASS}${NC}  ← save this!"
fi

COOKIE_SECRET=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32 || true)

# Resolve protocol once — avoids the "http${INSTALL_SSL:+s}" pitfall
if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then PROTO="https"; else PROTO="http"; fi

# ════════════════════════════════════════════════════════════
# PREFLIGHT
# ════════════════════════════════════════════════════════════
banner "Preflight checks"

# Root
if [[ $EUID -ne 0 ]]; then
    fail "Run as root:  sudo bash install.sh"
fi
ok "Running as root"

# Ubuntu 24.04 — hard requirement
if [[ ! -f /etc/os-release ]]; then
    fail "/etc/os-release not found — cannot detect OS."
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "This installer only supports Ubuntu. Detected OS: ${ID:-unknown}"
fi
if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    fail "This installer requires Ubuntu 24.04. Detected: Ubuntu ${VERSION_ID:-?}"
fi
ok "Ubuntu 24.04 confirmed"

# Internet connectivity
if ! curl -fsSL --max-time 15 https://github.com >/dev/null 2>&1; then
    fail "Cannot reach github.com. Check your DNS and outbound firewall rules."
fi
ok "Internet connectivity OK"

# Disk space — need >= 1 GB free on /opt
FREE_KB=$(df /opt --output=avail -k | tail -1)
if (( FREE_KB < 1048576 )); then
    warn "Less than 1 GB free on /opt (${FREE_KB} kB). Install may fail."
fi
ok "Disk space: $((FREE_KB / 1024)) MB free on /opt"

# Port pre-check (warn only — installer will free them)
for p in 80 8080 3000; do
    if ss -tlnp 2>/dev/null | grep -q ":${p}[[:space:]]"; then
        warn "Port $p is already in use. Installer will attempt to free it."
    fi
done
ok "Port pre-check done"

banner "Headscale & Headplane Installer
  VPN domain   : ${DOMAIN}
  Panel domain : ${UI_DOMAIN}
  Headscale    : ${HEADSCALE_VERSION}
  Headplane    : ${HEADPLANE_TAG}
  Protocol     : ${PROTO}"

# ════════════════════════════════════════════════════════════
# STEP 1 — System dependencies
# ════════════════════════════════════════════════════════════
step 1 "System dependencies"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    curl gnupg git wget jq ca-certificates iproute2 \
    nginx supervisor certbot python3-certbot-nginx
ok "Base packages installed"

info "Setting up Node.js 22…"
rm -f /etc/apt/sources.list.d/nodesource.list
retry 3 5 curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
apt-get remove -y nodejs 2>/dev/null || true
apt-get install -y --no-install-recommends nodejs
ok "Node.js installed: $(node --version)"

# ════════════════════════════════════════════════════════════
# STEP 2 — Headscale binary + config + service
# ════════════════════════════════════════════════════════════
step 2 "Headscale ${HEADSCALE_VERSION}"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  HS_ARCH="amd64" ;;
    aarch64) HS_ARCH="arm64" ;;
    *)       fail "Unsupported CPU architecture: $ARCH" ;;
esac

HS_BIN="headscale_${HEADSCALE_VERSION}_linux_${HS_ARCH}"
RELEASE_BASE="https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}"

info "Downloading headscale ${HEADSCALE_VERSION} (${HS_ARCH})…"
retry 3 5 curl -fsSLo /tmp/headscale        "${RELEASE_BASE}/${HS_BIN}"
retry 3 5 curl -fsSLo /tmp/headscale.sha256 "${RELEASE_BASE}/checksums.txt"

info "Verifying checksum…"
EXPECTED=$(grep "${HS_BIN}$" /tmp/headscale.sha256 | awk '{print $1}')
ACTUAL=$(sha256sum /tmp/headscale | awk '{print $1}')
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    rm -f /tmp/headscale /tmp/headscale.sha256
    fail "Checksum mismatch!\n  expected : $EXPECTED\n  actual   : $ACTUAL"
fi
ok "Checksum verified"
rm -f /tmp/headscale.sha256

install -m 0755 /tmp/headscale /usr/local/bin/headscale
rm -f /tmp/headscale

mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale

info "Fetching default config…"
retry 3 5 curl -fsSLo /etc/headscale/config.yaml \
    "https://raw.githubusercontent.com/juanfont/headscale/v${HEADSCALE_VERSION}/config-example.yaml"

sed -i "s|^server_url: .*|server_url: ${PROTO}://${DOMAIN}|"          /etc/headscale/config.yaml
sed -i "s|^listen_addr: .*|listen_addr: 127.0.0.1:8080|"              /etc/headscale/config.yaml
sed -i "s|^grpc_listen_addr: .*|grpc_listen_addr: 127.0.0.1:50443|"   /etc/headscale/config.yaml

headscale -c /etc/headscale/config.yaml version \
    || fail "Headscale binary failed sanity check (see log for details)."
ok "Headscale binary OK ($(headscale version))"

# Supervisor service
cat > /etc/supervisor/conf.d/headscale.conf <<'SUPERVISORCFG'
[program:headscale]
command=/usr/local/bin/headscale serve -c /etc/headscale/config.yaml
directory=/var/lib/headscale
autostart=true
autorestart=true
startretries=5
stopwaitsecs=10
stderr_logfile=/var/log/supervisor/headscale.err.log
stdout_logfile=/var/log/supervisor/headscale.out.log
user=root
SUPERVISORCFG

# Stop any stale instance so the port is free
supervisorctl stop headscale 2>/dev/null || true
pkill -f "headscale serve" 2>/dev/null || true
sleep 2
if command -v fuser &>/dev/null; then
    fuser -k 8080/tcp 2>/dev/null || true
fi

# Ensure supervisord is running
if ! pgrep -x supervisord &>/dev/null; then
    if [[ -f /etc/init.d/supervisor ]]; then
        /etc/init.d/supervisor start
    else
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    fi
    sleep 2
fi

supervisorctl update
sleep 1
supervisorctl start headscale

wait_port "Headscale" 8080 30

HS_STATUS=$(supervisorctl status headscale | awk '{print $2}')
if [[ "$HS_STATUS" != "RUNNING" ]]; then
    echo -e "\n${RED}${BOLD}--- Headscale error log ---${NC}" >&2
    tail -40 /var/log/supervisor/headscale.err.log >&2
    echo -e "${RED}---${NC}" >&2
    fail "Headscale supervisor status: '$HS_STATUS' (expected RUNNING)."
fi
ok "Headscale running (supervisor: RUNNING)"

# Nginx vhost for Headscale
cat > /etc/nginx/sites-available/headscale <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/headscale /etc/nginx/sites-enabled/headscale
rm -f /etc/nginx/sites-enabled/default
nginx -t || fail "Nginx config test failed for headscale vhost."
# start nginx if not yet running, otherwise reload live config
nginx -s reload 2>/dev/null || service nginx start
ok "Nginx configured for ${DOMAIN}"

if [[ "$PROTO" == "https" ]]; then
    info "Requesting Let's Encrypt certificate for ${DOMAIN}…"
    certbot --nginx --non-interactive --agree-tos \
        --register-unsafely-without-email -d "${DOMAIN}" \
        || warn "Certbot failed for ${DOMAIN}. Check DNS propagation and try manually."
    ok "SSL certificate installed for ${DOMAIN}"
fi

# ════════════════════════════════════════════════════════════
# STEP 3 — Headplane (Node.js web UI)
# ════════════════════════════════════════════════════════════
step 3 "Headplane ${HEADPLANE_TAG}"

info "Cloning headplane ${HEADPLANE_TAG}…"
rm -rf /opt/headplane
retry 3 10 git -c advice.detachedHead=false clone --depth 1 \
    --branch "${HEADPLANE_TAG}" \
    https://github.com/tale/headplane.git /opt/headplane
cd /opt/headplane

info "Installing pnpm and building (this may take a few minutes)…"
npm install -g pnpm --silent
pnpm install --silent
pnpm run build
ok "Headplane built"

# Wait for Headscale API to be ready before creating an API key
info "Waiting for Headscale API socket…"
API_READY=false
for i in $(seq 1 20); do
    if headscale -c /etc/headscale/config.yaml apikeys list &>/dev/null; then
        ok "Headscale API ready (after ${i}x2s)"
        API_READY=true
        break
    fi
    sleep 2
done
if [[ "$API_READY" != "true" ]]; then
    echo -e "\n${RED}${BOLD}--- Headscale error log ---${NC}" >&2
    tail -40 /var/log/supervisor/headscale.err.log >&2
    fail "Headscale API not ready after 40s."
fi

HEADSCALE_KEY=$(headscale -c /etc/headscale/config.yaml apikeys create -e 90d)
if [[ -z "$HEADSCALE_KEY" ]]; then
    supervisorctl status headscale >&2
    tail -20 /var/log/supervisor/headscale.err.log >&2
    fail "Failed to create Headscale API key."
fi
ok "Headscale API key created"

mkdir -p /etc/headplane
cat > /etc/headplane/config.yaml <<EOF
headscale:
  url: http://127.0.0.1:8080
  api_key: "${HEADSCALE_KEY}"
server:
  cookie_secret: "${COOKIE_SECRET}"
  disable_oidc: true
  admin_users:
    - admin
auth:
  basic:
    user: admin
    pass: "${ADMIN_PASS}"
EOF
chmod 600 /etc/headplane/config.yaml
ok "Headplane config written to /etc/headplane/config.yaml"

# Startup wrapper — exports config path so headplane can locate it
cat > /opt/headplane/start.sh <<'STARTSH'
#!/bin/bash
export HEADPLANE_CONFIG=/etc/headplane/config.yaml
export CONFIG_FILE=/etc/headplane/config.yaml
exec /usr/bin/node /opt/headplane/build/server/index.js
STARTSH
chmod +x /opt/headplane/start.sh

cat > /etc/supervisor/conf.d/headplane.conf <<'SUPERVISORCFG'
[program:headplane]
command=/opt/headplane/start.sh
directory=/opt/headplane
autostart=true
autorestart=true
startretries=5
stopwaitsecs=10
stderr_logfile=/var/log/supervisor/headplane.err.log
stdout_logfile=/var/log/supervisor/headplane.out.log
user=root
SUPERVISORCFG

supervisorctl update
supervisorctl restart headplane 2>/dev/null || supervisorctl start headplane

wait_port "Headplane" 3000 60

HP_STATUS=$(supervisorctl status headplane | awk '{print $2}')
if [[ "$HP_STATUS" != "RUNNING" ]]; then
    echo -e "\n${RED}${BOLD}--- Headplane error log ---${NC}" >&2
    tail -40 /var/log/supervisor/headplane.err.log >&2
    echo -e "${RED}---${NC}" >&2
    fail "Headplane supervisor status: '$HP_STATUS' (expected RUNNING)."
fi
ok "Headplane running (supervisor: RUNNING)"

# ════════════════════════════════════════════════════════════
# STEP 4 — Nginx reverse-proxy for Headplane + SSL
# ════════════════════════════════════════════════════════════
step 4 "Nginx reverse-proxy for Headplane"

cat > /etc/nginx/sites-available/headplane <<EOF
server {
    listen 80;
    server_name ${UI_DOMAIN};
    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/headplane /etc/nginx/sites-enabled/headplane
nginx -t || fail "Nginx config test failed for headplane vhost."
# start nginx if not yet running, otherwise reload live config
nginx -s reload 2>/dev/null || service nginx start
ok "Nginx configured for ${UI_DOMAIN}"

if [[ "$PROTO" == "https" ]]; then
    info "Requesting Let's Encrypt certificate for ${UI_DOMAIN}…"
    certbot --nginx --non-interactive --agree-tos \
        --register-unsafely-without-email -d "${UI_DOMAIN}" \
        || warn "Certbot failed for ${UI_DOMAIN}. Check DNS propagation and try manually."
    ok "SSL certificate installed for ${UI_DOMAIN}"
fi

# ════════════════════════════════════════════════════════════
# Done
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  INSTALLATION COMPLETE!${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "  VPN Server    : ${BOLD}${PROTO}://${DOMAIN}${NC}"
echo -e "  Control Panel : ${BOLD}${PROTO}://${UI_DOMAIN}${NC}"
echo -e "  Username      : ${BOLD}admin${NC}"
echo -e "  Password      : ${BOLD}${ADMIN_PASS}${NC}"
echo -e "  Log file      : ${DIM}${LOG_FILE}${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
