// ================================================================
// Application state
// ================================================================
let currentStepIndex = 0;

// ================================================================
// DOM references
// ================================================================
const dom = {
    domainInput:           document.getElementById('domainInput'),
    uiDomainInput:         document.getElementById('uiDomainInput'),
    headscaleVersionInput: document.getElementById('headscaleVersionInput'),
    headplaneVersionInput: document.getElementById('headplaneVersionInput'),
    adminPassInput:        document.getElementById('adminPassInput'),
    nav:                   document.getElementById('stepNavigation'),
    title:                 document.getElementById('contentTitle'),
    desc:                  document.getElementById('contentDesc'),
    text:                  document.getElementById('contentText'),
    codeCont:              document.getElementById('codeContainer'),
    code:                  document.getElementById('contentCode'),
    copyBtn:               document.getElementById('copyButton'),
    prevBtn:               document.getElementById('prevBtn'),
    nextBtn:               document.getElementById('nextBtn')
};

// ================================================================
// Helpers
// ================================================================

/** Replace all wizard placeholders in a string with current values. */
function applyPlaceholders(str) {
    if (!str) return '';
    return str
        .replace(/\{\{DOMAIN\}\}/g,            dom.domainInput.value.trim()           || 'headscale.visiosoft.com.tr')
        .replace(/\{\{UI_DOMAIN\}\}/g,         dom.uiDomainInput.value.trim()         || 'head.visiosoft.com.tr')
        .replace(/\{\{ADMIN_PASS\}\}/g,        dom.adminPassInput.value.trim()        || 'enter_password')
        .replace(/\{\{HEADSCALE_VERSION\}\}/g, dom.headscaleVersionInput.value.trim() || '0.28.0')
        .replace(/\{\{HEADPLANE_TAG\}\}/g,     dom.headplaneVersionInput.value.trim() || 'v0.6.2');
}

/** Generate a cryptographically secure random 16-character alphanumeric password. */
function generatePassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const bytes = new Uint8Array(16);
    window.crypto.getRandomValues(bytes);
    return Array.from(bytes, b => chars[b % chars.length]).join('');
}

// ================================================================
// Render functions
// ================================================================

/** Rebuild the sidebar navigation with correct active state. */
function renderNav() {
    dom.nav.innerHTML = '';
    STEPS.forEach((step, index) => {
        const isActive = index === currentStepIndex;

        const btn = document.createElement('button');
        btn.className = `w-full text-left px-5 py-4 rounded-xl border-2 font-medium transition-all duration-200
                         flex items-center gap-3 group ${isActive ? 'step-active shadow-md' : 'step-inactive'}`;

        // Numbered circle
        const circle = document.createElement('div');
        circle.className = `w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold
                            ${isActive ? 'bg-white text-teal-600' : 'bg-stone-200 text-stone-600 group-hover:bg-stone-300'}`;
        circle.textContent = index + 1;

        // Step label (text after the colon, fallback to full title)
        const label = document.createElement('span');
        label.textContent = step.title.split(': ')[1] ?? step.title;

        btn.append(circle, label);
        btn.addEventListener('click', () => goToStep(index));
        dom.nav.appendChild(btn);
    });
}

/** Populate the content area for the current step. */
function renderContent() {
    const step = STEPS[currentStepIndex];

    dom.title.textContent = step.title;
    dom.desc.textContent  = step.desc;
    dom.text.innerHTML    = applyPlaceholders(step.text);

    if (step.code) {
        dom.codeCont.classList.remove('hidden');
        dom.code.textContent   = applyPlaceholders(step.code);
        dom.copyBtn.textContent          = 'Copy';
        dom.copyBtn.style.backgroundColor = '#44403c';
    } else {
        dom.codeCont.classList.add('hidden');
    }

    dom.prevBtn.classList.toggle('hidden', currentStepIndex === 0);
    dom.nextBtn.classList.toggle('hidden', currentStepIndex === STEPS.length - 1);
}

/** Navigate to a specific step index and refresh the UI. */
function goToStep(index) {
    currentStepIndex = index;
    renderNav();
    renderContent();
}

// ================================================================
// Copy-to-clipboard
// ================================================================
dom.copyBtn.addEventListener('click', () => {
    const text = dom.code.textContent;

    const finish = (ok) => {
        dom.copyBtn.textContent           = ok ? 'Copied!' : 'Error!';
        dom.copyBtn.style.backgroundColor = ok ? '#059669' : '#dc2626';
        setTimeout(() => {
            dom.copyBtn.textContent           = 'Copy';
            dom.copyBtn.style.backgroundColor = '#44403c';
        }, 2000);
    };

    if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => finish(true)).catch(() => finish(false));
    } else {
        const ta = Object.assign(document.createElement('textarea'), {
            value: text,
            style: 'position:absolute;left:-9999px'
        });
        document.body.appendChild(ta);
        ta.select();
        const ok = document.execCommand('copy');
        document.body.removeChild(ta);
        finish(ok);
    }
});

// ================================================================
// Previous / Next buttons
// ================================================================
dom.prevBtn.addEventListener('click', () => { if (currentStepIndex > 0) goToStep(currentStepIndex - 1); });
dom.nextBtn.addEventListener('click', () => { if (currentStepIndex < STEPS.length - 1) goToStep(currentStepIndex + 1); });

// ================================================================
// Live-update code blocks when wizard inputs change
// ================================================================
[
    dom.domainInput, 
    dom.uiDomainInput, 
    dom.headscaleVersionInput, 
    dom.headplaneVersionInput, 
    dom.adminPassInput
].forEach(input => input.addEventListener('input', renderContent));

// ================================================================
// Bootstrap
// ================================================================
dom.adminPassInput.value = generatePassword();
goToStep(0);
