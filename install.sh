#!/bin/bash
# ==============================================================================
# Headscale + Headplane — Ubuntu 24.04 Standalone Installer
# Usage: bash install.sh [--domain head.example.com] [--ui-domain headscale.example.com]
#        [--admin-pass yourpassword] [--headscale-version 0.28.0]
#        [--headplane-tag v0.6.2] [--no-ssl]
# ==============================================================================
set -eu

# ------------------------------------------------------------------------------
# Defaults (override via args or env vars set by the web wizard)
# ------------------------------------------------------------------------------
DOMAIN="${DOMAIN:-headscale.visiosoft.com.tr}"
UI_DOMAIN="${UI_DOMAIN:-head.visiosoft.com.tr}"
ADMIN_PASS="${ADMIN_PASS:-}"
HEADSCALE_VERSION="${HEADSCALE_VERSION:-0.28.0}"
HEADPLANE_TAG="${HEADPLANE_TAG:-v0.6.2}"
INSTALL_SSL=""

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)           DOMAIN="$2";           shift 2 ;;
    --ui-domain)        UI_DOMAIN="$2";        shift 2 ;;
    --admin-pass)       ADMIN_PASS="$2";       shift 2 ;;
    --headscale-version) HEADSCALE_VERSION="$2"; shift 2 ;;
    --headplane-tag)    HEADPLANE_TAG="$2";    shift 2 ;;
    --no-ssl)           INSTALL_SSL="n";       shift   ;;
    --ssl)              INSTALL_SSL="y";       shift   ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Ask interactively if not set
if [[ -z "$INSTALL_SSL" ]]; then
  read -rp "Install SSL Certificate (Let's Encrypt)? (y/n): " INSTALL_SSL
fi

# Generate admin password if not provided
if [[ -z "$ADMIN_PASS" ]]; then
  ADMIN_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
  echo "Generated admin password: $ADMIN_PASS  (save this!)"
fi

# Cookie secret — separate from login password
COOKIE_SECRET=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)

echo "=================================================="
echo " Headscale & Headplane Installer"
echo "  VPN domain  : $DOMAIN"
echo "  Panel domain: $UI_DOMAIN"
echo "  Headscale   : $HEADSCALE_VERSION"
echo "  Headplane   : $HEADPLANE_TAG"
echo "=================================================="

# ------------------------------------------------------------------------------
# 0/4  System dependencies
# ------------------------------------------------------------------------------
echo "0/4: Updating system and installing dependencies..."
apt-get update
apt-get install -y curl gnupg git wget jq
# Remove old nodesource lists to ensure clean downgrade if needed
rm -f /etc/apt/sources.list.d/nodesource.list
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get remove -y nodejs || true
apt-get install -y nodejs nginx supervisor certbot python3-certbot-nginx

# ------------------------------------------------------------------------------
# 1/4  Headscale core binary + config
# ------------------------------------------------------------------------------
echo "1/4: Installing Headscale Core..."

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  HS_ARCH="amd64" ;;
    aarch64) HS_ARCH="arm64" ;;
    *)       echo "ERROR: Unsupported architecture $ARCH"; exit 1 ;;
esac

HEADSCALE_BIN="headscale_${HEADSCALE_VERSION}_linux_${HS_ARCH}"
RELEASE_BASE="https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}"

curl -sLo /tmp/headscale        "${RELEASE_BASE}/${HEADSCALE_BIN}"
curl -sLo /tmp/headscale.sha256 "${RELEASE_BASE}/checksums.txt"

grep "${HEADSCALE_BIN}\$" /tmp/headscale.sha256 \
    | awk '{print $1 "  /tmp/headscale"}' \
    | sha256sum -c - \
    || { echo "ERROR: Checksum verification failed! Aborting."; exit 1; }

install -m 0755 /tmp/headscale /usr/local/bin/headscale
rm /tmp/headscale /tmp/headscale.sha256

mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale
curl -so /etc/headscale/config.yaml \
  "https://raw.githubusercontent.com/juanfont/headscale/v${HEADSCALE_VERSION}/config-example.yaml"

# Sanitize config: use line-start anchor to avoid touching comment lines
if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    sed -i "s|^server_url: .*|server_url: https://${DOMAIN}|g" /etc/headscale/config.yaml
else
    sed -i "s|^server_url: .*|server_url: http://${DOMAIN}|g"  /etc/headscale/config.yaml
fi
sed -i "s|^listen_addr: .*|listen_addr: 127.0.0.1:8080|g"       /etc/headscale/config.yaml
sed -i "s|^grpc_listen_addr: .*|grpc_listen_addr: 127.0.0.1:50443|g" /etc/headscale/config.yaml

# Verify config is valid before handing off to supervisor
echo "Validating Headscale config..."
headscale -c /etc/headscale/config.yaml version || {
    echo "ERROR: Headscale binary failed to run. Config or binary issue."
    echo "Config dump:"
    cat /etc/headscale/config.yaml
    exit 1
}

# ------------------------------------------------------------------------------
# 2/4  Headscale supervisor service + Nginx reverse-proxy
# ------------------------------------------------------------------------------
echo "2/4: Configuring Headscale Supervisor service and Nginx proxy..."

cat > /etc/supervisor/conf.d/headscale.conf <<EOF
[program:headscale]
command=/usr/local/bin/headscale serve -c /etc/headscale/config.yaml
directory=/var/lib/headscale
autostart=true
autorestart=true
startretries=5
stderr_logfile=/var/log/supervisor/headscale.err.log
stdout_logfile=/var/log/supervisor/headscale.out.log
user=root
EOF

# Kill any existing headscale that might hold port 8080 (idempotent re-runs)
supervisorctl stop headscale 2>/dev/null || true
pkill -f "headscale serve" 2>/dev/null || true
sleep 2

# Ensure port 8080 is clear
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8080/tcp 2>/dev/null || true
fi

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    if [ -f /etc/init.d/supervisor ]; then
        /etc/init.d/supervisor start
    else
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    fi
fi
sleep 3

supervisorctl update
sleep 2

supervisorctl start headscale
sleep 5

HS_STATUS=$(supervisorctl status headscale | awk '{print $2}')
if [[ "$HS_STATUS" != "RUNNING" ]]; then
    echo "ERROR: Headscale failed to start. Status: $HS_STATUS"
    echo "--- headscale error log ---"
    cat /var/log/supervisor/headscale.err.log
    echo "---"
    exit 1
fi
echo "Headscale is running."

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
    }
}
EOF
ln -sf /etc/nginx/sites-available/headscale /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && service nginx reload

[[ "$INSTALL_SSL" =~ ^[Yy]$ ]] && certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "${DOMAIN}"

# ------------------------------------------------------------------------------
# 3/4  Headplane (Node.js web UI)
# ------------------------------------------------------------------------------
echo "3/4: Installing Headplane App (this may take a few minutes)..."

cd /opt && rm -rf headplane
git -c advice.detachedHead=false clone --depth 1 --branch "${HEADPLANE_TAG}" https://github.com/tale/headplane.git
cd headplane
npm install -g pnpm
pnpm install
pnpm run build

echo "Waiting for Headscale socket to be ready..."
for i in $(seq 1 15); do
    if headscale -c /etc/headscale/config.yaml apikeys list >/dev/null 2>&1; then
        echo "Headscale socket ready after ${i}s."
        break
    fi
    sleep 2
done

HEADSCALE_KEY=$(headscale -c /etc/headscale/config.yaml apikeys create -e 90d)
if [[ -z "$HEADSCALE_KEY" ]]; then
    echo "ERROR: Failed to create API key. Is headscale running?"
    supervisorctl status headscale
    cat /var/log/supervisor/headscale.err.log
    exit 1
fi

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

# Create headplane startup wrapper
cat > /opt/headplane/start.sh <<'STARTSH'
#!/bin/bash
exec /usr/bin/node /opt/headplane/build/server/index.js
STARTSH
chmod +x /opt/headplane/start.sh

cat > /etc/supervisor/conf.d/headplane.conf <<EOF
[program:headplane]
command=/opt/headplane/start.sh
directory=/opt/headplane
autostart=true
autorestart=true
startretries=5
stderr_logfile=/var/log/supervisor/headplane.err.log
stdout_logfile=/var/log/supervisor/headplane.out.log
user=root
EOF

supervisorctl update
supervisorctl restart headplane

# ------------------------------------------------------------------------------
# 4/4  Headplane Nginx reverse-proxy
# ------------------------------------------------------------------------------
echo "4/4: Configuring Headplane Nginx proxy..."

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
    }
}
EOF
ln -sf /etc/nginx/sites-available/headplane /etc/nginx/sites-enabled/
nginx -t && service nginx reload

[[ "$INSTALL_SSL" =~ ^[Yy]$ ]] && certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "${UI_DOMAIN}"

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
echo ""
echo "==========================================="
echo " INSTALLATION COMPLETE!"
echo "==========================================="
echo " VPN Server  : http${INSTALL_SSL:+s}://${DOMAIN}"
echo " Control Panel: http${INSTALL_SSL:+s}://${UI_DOMAIN}"
echo " Username    : admin"
echo " Password    : ${ADMIN_PASS}"
echo "==========================================="
