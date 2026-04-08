// Options page script
const providerBtns = document.querySelectorAll('[data-provider]');
const chatgptSection = document.getElementById('chatgpt-section');
const geminiSection = document.getElementById('gemini-section');
const openevidenceSection = document.getElementById('openevidence-section');
const providerInput = document.getElementById('provider');
const statusDiv = document.getElementById('status');
const shortcutInput = document.getElementById('shortcut');
const testButtons = {
  chatgpt: document.getElementById('test-chatgpt'),
  gemini: document.getElementById('test-gemini'),
  openevidence: document.getElementById('test-openevidence')
};
const testStatus = {
  chatgpt: document.getElementById('test-chatgpt-status'),
  gemini: document.getElementById('test-gemini-status'),
  openevidence: document.getElementById('test-openevidence-status')
};

function setTestStatus(provider, message, type = '') {
  const el = testStatus[provider];
  if (!el) return;
  el.textContent = message;
  el.className = `test-status${type ? ` ${type}` : ''}`;
}

function getProviderKey(provider) {
  if (provider === 'chatgpt') return document.getElementById('chatgpt-key').value.trim();
  if (provider === 'gemini') return document.getElementById('gemini-key').value.trim();
  if (provider === 'openevidence') return document.getElementById('openevidence-key').value.trim();
  return '';
}

async function testConnection(provider) {
  const apiKey = getProviderKey(provider);
  if (!apiKey) {
    setTestStatus(provider, 'Enter API key first.', 'error');
    return;
  }

  const btn = testButtons[provider];
  if (btn) btn.disabled = true;
  setTestStatus(provider, 'Testing connection...');

  try {
    const result = await chrome.runtime.sendMessage({
      type: 'TEST_AI_CONNECTION',
      provider,
      apiKey
    });

    if (result && result.success) {
      setTestStatus(provider, result.message || 'Connection successful.', 'success');
    } else {
      setTestStatus(provider, (result && result.error) || 'Connection failed.', 'error');
    }
  } catch (error) {
    setTestStatus(provider, error.message || 'Connection failed.', 'error');
  } finally {
    if (btn) btn.disabled = false;
  }
}

Object.entries(testButtons).forEach(([provider, btn]) => {
  if (!btn) return;
  btn.addEventListener('click', () => testConnection(provider));
});

// Load settings from sync storage (persists permanently and across devices)
chrome.storage.sync.get(['provider', 'chatgpt_key', 'gemini_key', 'openevidence_key', 'shortcut'], (result) => {
  const provider = result.provider || 'chatgpt';
  providerInput.value = provider;

  shortcutInput.value = result.shortcut || 'Alt+Space';
  
  if (result.chatgpt_key) {
    document.getElementById('chatgpt-key').value = result.chatgpt_key;
  }
  if (result.gemini_key) {
    document.getElementById('gemini-key').value = result.gemini_key;
  }
  if (result.openevidence_key) {
    document.getElementById('openevidence-key').value = result.openevidence_key;
  }
  
  updateUI(provider);
});

// Provider toggle
providerBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    const provider = btn.dataset.provider;
    providerInput.value = provider;
    updateUI(provider);
  });
});

function updateUI(provider) {
  providerBtns.forEach(btn => {
    btn.classList.remove('active');
    if (btn.dataset.provider === provider) {
      btn.classList.add('active');
    }
  });

  if (provider === 'chatgpt') {
    chatgptSection.style.display = 'block';
    geminiSection.style.display = 'none';
    openevidenceSection.style.display = 'none';
  } else if (provider === 'gemini') {
    chatgptSection.style.display = 'none';
    geminiSection.style.display = 'block';
    openevidenceSection.style.display = 'none';
  } else if (provider === 'openevidence') {
    chatgptSection.style.display = 'none';
    geminiSection.style.display = 'none';
    openevidenceSection.style.display = 'block';
  }
}

// Save
document.getElementById('save').addEventListener('click', () => {
  const provider = providerInput.value;
  const chatgptKey = document.getElementById('chatgpt-key').value.trim();
  const geminiKey = document.getElementById('gemini-key').value.trim();
  const openevidenceKey = document.getElementById('openevidence-key').value.trim();
  const shortcut = shortcutInput.value.trim() || 'Alt+Space';

  if (provider === 'chatgpt' && !chatgptKey) {
    showStatus('Please enter your ChatGPT API key', 'error');
    return;
  }

  if (provider === 'gemini' && !geminiKey) {
    showStatus('Please enter your Gemini API key', 'error');
    return;
  }

  if (provider === 'openevidence' && !openevidenceKey) {
    showStatus('Please enter your Open Evidence API key', 'error');
    return;
  }

  chrome.storage.sync.set({
    provider,
    chatgpt_key: chatgptKey,
    gemini_key: geminiKey,
    openevidence_key: openevidenceKey,
    shortcut
  }, () => {
    showStatus('✓ Settings saved permanently! 💾', 'success');
    setTimeout(() => statusDiv.classList.remove('success'), 3000);
  });
});

// Reset
document.getElementById('reset').addEventListener('click', () => {
  document.getElementById('chatgpt-key').value = '';
  document.getElementById('gemini-key').value = '';
  document.getElementById('openevidence-key').value = '';
  shortcutInput.value = 'Alt+Space';
  showStatus('Fields cleared', 'success');
  setTimeout(() => statusDiv.classList.remove('success'), 2000);
});

function showStatus(message, type) {
  statusDiv.textContent = message;
  statusDiv.className = `status ${type}`;
}
