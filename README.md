# Headscale & Headplane — Interactive Installation Guide

An interactive, single-page installation assistant for **Headscale** (self-hosted Tailscale control server) and **Headplane** (web UI for Headscale) on **Ubuntu 24 LTS**.

🔗 **Installation Script:** 
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/fatihalp/headscale-headplane/refs/heads/main/install.sh)
```

---

## What is this?

| Component | Description |
|-----------|-------------|
| **Headscale** | Open-source, self-hosted implementation of the Tailscale control server |
| **Headplane** | Web UI that lets you manage Headscale without the CLI |

This repository provides an **interactive HTML wizard** (`index.html`) and a **standalone bash script** (`install.sh`) that:

- Installs and configures Headscale, Headplane, Nginx, and (optionally) Let's Encrypt SSL.
- Uses **Supervisor** for process management on a bare Ubuntu 24.04 server.
- Automatically handles dependencies like Node.js, Nginx, and Certbot.

---

## Quick Start (Ubuntu 24 LTS)

### Prerequisites

- A fresh Ubuntu 24.04 LTS server.
- Two DNS A-records pointing to your server's IP (e.g., `headscale.visiosoft.com.tr` and `head.visiosoft.com.tr`).
- Root access.

### 1. Open the installation wizard

You can run the interactive guide locally with:

```bash
npm start
```

---

### 2. Fill in the wizard fields

| Field | Example | Description |
|-------|---------|-------------|
| **VPN Domain** | `head.example.com` | Domain for the Headscale control server |
| **Panel Domain** | `headscale.example.com` | Domain for the Headplane web UI |
| **Password** | *(auto-generated)* | Login password for the Headplane panel |

All code blocks update **live** as you type.

### 3. Copy and run the install script

Click **"Kopyala"** (Copy) on Step 2 and paste the script into your server terminal as root:

```bash
sudo -i
# paste the copied script here
```

The script will:
1. Download and configure the **Headscale** binary
2. Register Headscale as a **Supervisor** daemon
3. Create an **Nginx** reverse-proxy virtual host for the VPN domain
4. Clone, build, and start **Headplane** as a systemd service
5. Create an **Nginx** reverse-proxy virtual host for the panel domain
6. Optionally install **Let's Encrypt SSL** via Certbot for both domains

### 4. Connect a device

After installation, run on any client machine:

```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to your self-hosted control server
sudo tailscale up --login-server=https://head.example.com
```

---

---

## References

- [Headscale](https://github.com/juanfont/headscale) — Self-hosted Tailscale control server
- [Headplane](https://github.com/tale/headplane) — Web UI for Headscale
- [Tailscale](https://tailscale.com) — VPN mesh networking client

---

## License

[MIT](LICENSE)
