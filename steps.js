const STEPS = [
    {
        id: 1,
        title: "Step 1: Server Preparation",
        desc: "Ensure you have a fresh Ubuntu 24.04 server.",
        text: `<p>You will need a completely fresh, bare Ubuntu 24.04 server. The script in the next step will automatically install Nginx, Supervisor, Node.js, Certbot, and all other necessary dependencies.</p>
        <p class="mt-4">Make sure your domains <strong>{{DOMAIN}}</strong> and <strong>{{UI_DOMAIN}}</strong> are pointing to your server's IP address before proceeding, especially if you plan to install SSL.</p>`,
        code: null
    },
    {
        id: 2,
        title: "Step 2: One-Click Full Installation (SSH)",
        desc: "Dependencies, Headscale, Headplane, Nginx, SSL, and Supervisor settings are handled automatically.",
        text: `<p>When you paste the script below into your terminal, it will first
<strong>ask if you want to install SSL</strong>. If you confirm, it will run the standard
Certbot steps (email, etc.).</p>`,
        code: `DOMAIN="{{DOMAIN}}"
UI_DOMAIN="{{UI_DOMAIN}}"
ADMIN_PASS="{{ADMIN_PASS}}"
HEADSCALE_VERSION="{{HEADSCALE_VERSION}}"
HEADPLANE_TAG="{{HEADPLANE_TAG}}"
# Cookie secret is separate from the login password for better security
COOKIE_SECRET=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)

read -p "Install SSL Certificate (Let's Encrypt)? (y/n): " INSTALL_SSL

echo "=================================================="
echo "Updating system and installing dependencies..."
echo "=================================================="
apt-get update
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs nginx supervisor certbot python3-certbot-nginx git curl wget jq

# ------------------------------------------------------------------
# 1/4  Headscale core binary + config
# ------------------------------------------------------------------
echo "1/4: Installing Headscale Core..."

HEADSCALE_BIN="headscale_\${HEADSCALE_VERSION}_linux_amd64"
RELEASE_BASE="https://github.com/juanfont/headscale/releases/download/v\${HEADSCALE_VERSION}"

# Download binary and official checksum file, then verify
curl -sLo /tmp/headscale          "\${RELEASE_BASE}/\${HEADSCALE_BIN}"
curl -sLo /tmp/headscale.sha256   "\${RELEASE_BASE}/headscale_\${HEADSCALE_VERSION}_checksums.txt"
grep "\${HEADSCALE_BIN}$" /tmp/headscale.sha256 | awk '{print $1 "  /tmp/headscale"}' | sha256sum -c - \\
    || { echo "Checksum verification failed! Installation aborted."; exit 1; }
install -m 0755 /tmp/headscale /usr/local/bin/headscale
rm /tmp/headscale /tmp/headscale.sha256

mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale
curl -so /etc/headscale/config.yaml \\
  https://raw.githubusercontent.com/juanfont/headscale/v\${HEADSCALE_VERSION}/config-example.yaml

if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
    sed -i "s|server_url: .*|server_url: https://$DOMAIN|g" /etc/headscale/config.yaml
else
    sed -i "s|server_url: .*|server_url: http://$DOMAIN|g"  /etc/headscale/config.yaml
fi
sed -i "s|listen_addr: .*|listen_addr: 127.0.0.1:8080|g" /etc/headscale/config.yaml

# ------------------------------------------------------------------
# 2/4  Headscale supervisor service + Nginx reverse-proxy
# ------------------------------------------------------------------
echo "2/4: Headscale Service and Proxy Settings..."

cat <<EOF | tee /etc/supervisor/conf.d/headscale.conf > /dev/null
[program:headscale]
command=/usr/local/bin/headscale serve -c /etc/headscale/config.yaml
directory=/var/lib/headscale
autostart=true
autorestart=true
user=root
EOF
supervisorctl update
supervisorctl restart headscale

cat <<EOF | tee /etc/nginx/sites-available/headscale > /dev/null
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \\$host;
    }
}
EOF
ln -sf /etc/nginx/sites-available/headscale /etc/nginx/sites-enabled/
systemctl restart nginx

[[ "$INSTALL_SSL" =~ ^[Yy]$ ]] && certbot --nginx -d "$DOMAIN"

# ------------------------------------------------------------------
# 3/4  Headplane (Node.js web UI) — pinned to a stable release tag
# ------------------------------------------------------------------
echo "3/4: Installing Headplane App..."

cd /opt && rm -rf headplane
git clone --depth 1 --branch "\$HEADPLANE_TAG" https://github.com/tale/headplane.git
cd headplane
npm install -g pnpm
pnpm install && pnpm run build

echo "Waiting for Headscale socket to be ready..."
sleep 6
HEADSCALE_KEY=\$(headscale -c /etc/headscale/config.yaml apikeys create -e 90d) \\
    || { echo "Failed to create API key! The service might not be ready."; exit 1; }

cat <<EOF | tee /opt/headplane/.env > /dev/null
HEADSCALE_URL=http://127.0.0.1:8080
HEADSCALE_API_KEY=\${HEADSCALE_KEY}
COOKIE_SECRET=\${COOKIE_SECRET}
DISABLE_OIDC=true
ADMIN_USERS=admin
BASIC_AUTH_USER=admin
BASIC_AUTH_PASS=$ADMIN_PASS
EOF

cat <<EOF | tee /etc/supervisor/conf.d/headplane.conf > /dev/null
[program:headplane]
command=bash -c 'set -a; source /opt/headplane/.env; set +a; exec /usr/bin/npm start'
directory=/opt/headplane
autostart=true
autorestart=true
user=root
EOF
supervisorctl update
supervisorctl restart headplane

# ------------------------------------------------------------------
# 4/4  Headplane Nginx reverse-proxy
# ------------------------------------------------------------------
echo "4/4: Headplane Proxy Settings..."

cat <<EOF | tee /etc/nginx/sites-available/headplane > /dev/null
server {
    listen 80;
    server_name $UI_DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \\$host;
    }
}
EOF
ln -sf /etc/nginx/sites-available/headplane /etc/nginx/sites-enabled/
systemctl restart nginx

[[ "$INSTALL_SSL" =~ ^[Yy]$ ]] && certbot --nginx -d "$UI_DOMAIN"

echo "==========================================="
echo "INSTALLATION COMPLETE! You can now visit the panel."`
    },
    {
        id: 3,
        title: "Step 3: Client Connection",
        desc: "Add your devices to the network.",
        text: `<p class="text-sm mb-4">First install the Tailscale client, then connect to your server.
You can access the panel at <code>http(s)://{{UI_DOMAIN}}</code>.</p>`,
        code: `# Install Tailscale client
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to Headscale server
sudo tailscale up --login-server=https://{{DOMAIN}}`
    }
];
