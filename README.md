# Headscale & Headplane — Interactive Installation Guide

An interactive, single-page installation assistant for **Headscale** (self-hosted Tailscale control server) and **Headplane** (web UI for Headscale) on **Ubuntu 24 LTS**.

🔗 **Live guide:** `https://<your-github-username>.github.io/headscale-headplane`

---

## What is this?

| Component | Description |
|-----------|-------------|
| **Headscale** | Open-source, self-hosted implementation of the Tailscale control server |
| **Headplane** | Web UI that lets you manage Headscale without the CLI |

This repository provides an **interactive HTML wizard** (`index.html`) that:

- Takes your domain names and generates a **ready-to-paste install script**
- Installs and configures Headscale, Headplane, Nginx, and (optionally) Let's Encrypt SSL
- Uses **VitoDeploy**-compatible service management (Supervisor + systemd)

---

## Quick Start (Ubuntu 24 LTS)

### Prerequisites

- Ubuntu 24.04 LTS server (fresh install recommended)
- Two DNS A-records pointing to your server's IP:
  - `head.example.com` → VPN control server
  - `headscale.example.com` → Web UI panel
- Root or `sudo` access
- **VitoDeploy** installed with **Nginx**, **Supervisor**, and **remote-monitor**

### 1. Open the installation wizard

Open `index.html` in any browser (the file works offline — no build step required).

```
open index.html          # macOS
xdg-open index.html      # Linux desktop
# or just drag the file into your browser
```

Or visit the hosted version at the GitHub Pages link above.

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

## File Structure

```
headscale-headplane/
├── index.html   # Interactive installation wizard (no build step needed)
├── README.md    # This file
└── LICENSE
```

### `index.html` internals

The file is intentionally **self-contained** (zero dependencies beyond a Tailwind CDN link):

```
index.html
├── <style>          — Base styles (step active/inactive, code block, copy button)
├── <header>         — Page header
├── <main>
│   ├── Wizard panel — Domain / password inputs (live placeholder replacement)
│   ├── Step nav     — Sidebar rendered by JS from STEPS array
│   └── Content area — Title, description, rich-text body, code block, prev/next
├── <footer>
└── <script>
    ├── STEPS[]      — All step data (title, description, HTML body, shell code)
    ├── Helpers      — applyPlaceholders(), generatePassword()
    ├── Render fns   — renderNav(), renderContent(), goToStep()
    ├── Copy btn     — Clipboard API with execCommand fallback
    └── Bootstrap    — Auto-generate password, render step 0
```

---

## Development

No build tooling is required. Edit `index.html` directly and refresh your browser.

### Adding a step

Open `index.html`, find the `STEPS` array in the `<script>` block, and append a new object:

```js
{
    id: 4,
    title: "Adım 4: My New Step",
    desc: "Short description shown under the title.",
    text: `<p>HTML content. Use <code>{{DOMAIN}}</code>, <code>{{UI_DOMAIN}}</code>,
           and <code>{{ADMIN_PASS}}</code> as live-replaced placeholders.</p>`,
    code: `# Shell commands shown in the dark code block
echo "{{DOMAIN}}"` // set to null if no code block is needed
}
```

### Placeholders

| Placeholder | Replaced with |
|-------------|---------------|
| `{{DOMAIN}}` | VPN domain input value |
| `{{UI_DOMAIN}}` | Panel domain input value |
| `{{ADMIN_PASS}}` | Generated / entered password |

---

## Deployment (GitHub Pages)

The wizard is published automatically via GitHub Pages from the `main` branch root.

To enable GitHub Pages on your own fork:

1. Go to **Settings → Pages**
2. Source: **Deploy from a branch**
3. Branch: `main`, folder: `/ (root)`
4. Click **Save** — the site will be live at `https://<your-github-username>.github.io/headscale-headplane`

---

## References

- [Headscale](https://github.com/juanfont/headscale) — Self-hosted Tailscale control server
- [Headplane](https://github.com/tale/headplane) — Web UI for Headscale
- [Tailscale](https://tailscale.com) — VPN mesh networking client
- [VitoDeploy](https://vitodeploy.com) — Laravel-based server management panel

---

## License

[MIT](LICENSE)
