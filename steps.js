const STEPS = [
    {
        id: 1,
        title: "Step 1: Server Preparation",
        desc: "Ensure you have a fresh Ubuntu 24.04 server.",
        text: `<p>You will need a completely fresh, bare Ubuntu 24.04 server. The script in the next step will automatically install <strong>Nginx, Supervisor, Node.js, Certbot</strong>, and all other necessary dependencies.</p>
        <p class="mt-4">Make sure your domains <strong>{{DOMAIN}}</strong> and <strong>{{UI_DOMAIN}}</strong> are pointing to your server's IP address before proceeding, especially if you plan to install SSL.</p>
        <p class="mt-4">You can also use the <code>install.sh</code> script directly on any Ubuntu 24.04 server:</p>
        <pre class="mt-2 bg-stone-100 text-stone-800 rounded p-3 font-mono text-sm">bash &lt;(curl -fsSL https://raw.githubusercontent.com/fatihalp/headscale-headplane/refs/heads/main/install.sh) \\
  --domain headscale.visiosoft.com.tr \\
  --ui-domain head.visiosoft.com.tr \\
  --headscale-version {{HEADSCALE_VERSION}} \\
  --headplane-tag {{HEADPLANE_TAG}}</pre>`,
        code: null
    },
    {
        id: 2,
        title: "Step 2: One-Click Full Installation (SSH)",
        desc: "Dependencies, Headscale, Headplane, Nginx, SSL, and Supervisor are all handled automatically.",
        text: `<p>Paste the script below into your terminal to begin. It will <strong>ask if you want to install SSL</strong> unless you already answered during setup.</p>`,
        codeFile: "install.sh",
        code: null  // loaded dynamically from install.sh
    },
    {
        id: 3,
        title: "Step 3: Docker Compose Installation",
        desc: "Alternatively, run everything using Docker Compose.",
        text: `<p>If you prefer Docker, save the configuration below as <code>docker-compose.yaml</code> and run:</p>
        <pre class="mt-2 bg-stone-100 text-stone-800 rounded p-3 font-mono text-sm">docker-compose up -d</pre>
        <p class="mt-4 text-xs text-stone-500 italic">Note: You must have a <code>config.yaml</code> file in a <code>./config</code> directory before starting.</p>`,
        code: `version: '3.9'
services:
  headscale:
    image: headscale/headscale:{{HEADSCALE_VERSION}}
    container_name: headscale
    volumes:
      - ./config:/etc/headscale
      - ./data:/var/lib/headscale
    ports:
      - "8080:8080"
      - "50443:50443"
    command: headscale serve
    restart: always

  headplane:
    image: ghcr.io/tale/headplane:latest
    container_name: headplane
    ports:
      - "3000:3000"
    environment:
      - HEADSCALE_URL=http://headscale:8080
      - COOKIE_SECRET=use-a-strong-secret-here
    restart: always`
    },
    {
        id: 4,
        title: "Step 4: Client Connection",
        desc: "Add your devices to the network.",
        text: `<p class="text-sm mb-4">First install the Tailscale client, then connect to your server.
You can access the panel at <code>http(s)://{{UI_DOMAIN}}</code>.</p>`,
        code: `# Install Tailscale client
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to Headscale server
sudo tailscale up --login-server=https://{{DOMAIN}}`
    }
];

// Load install.sh dynamically for step 2
fetch('install.sh')
    .then(r => r.text())
    .then(text => {
        const step = STEPS.find(s => s.codeFile === 'install.sh');
        if (step) {
            step.code = text;
            // Re-render if we're already on that step
            if (typeof renderContent === 'function') renderContent();
        }
    })
    .catch(() => {
        const step = STEPS.find(s => s.codeFile === 'install.sh');
        if (step) step.code = '# Could not load install.sh — make sure the file is being served correctly.';
    });
