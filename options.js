// Options page script
const providerBtns = document.querySelectorAll('[data-provider]');
const chatgptSection = document.getElementById('chatgpt-section');
const geminiSection = document.getElementById('gemini-section');
const pubmedSection = document.getElementById('pubmed-section');
const providerInput = document.getElementById('provider');
const statusDiv = document.getElementById('status');
const shortcutInput = document.getElementById('shortcut');
const disabledUrlInput = document.getElementById('disabled-url');
const disabledUrlStatus = document.getElementById('disabled-url-status');
const disabledList = document.getElementById('disabled-list');
let disabledRules = [];
const testButtons = {
  chatgpt: document.getElementById('test-chatgpt'),
  gemini: document.getElementById('test-gemini'),
  pubmed: document.getElementById('test-pubmed')
};
const testStatus = {
  chatgpt: document.getElementById('test-chatgpt-status'),
  gemini: document.getElementById('test-gemini-status'),
  pubmed: document.getElementById('test-pubmed-status')
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
  if (provider === 'pubmed') return document.getElementById('pubmed-key').value.trim();
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
chrome.storage.sync.get(['provider', 'chatgpt_key', 'gemini_key', 'pubmed_key', 'openevidence_key', 'shortcut', 'disabledRules'], (result) => {
  const provider = result.provider === 'openevidence' ? 'pubmed' : (result.provider || 'chatgpt');
  providerInput.value = provider;

  shortcutInput.value = result.shortcut || 'Alt+Space';
  
  if (result.chatgpt_key) {
    document.getElementById('chatgpt-key').value = result.chatgpt_key;
  }
  if (result.gemini_key) {
    document.getElementById('gemini-key').value = result.gemini_key;
  }
  if (result.pubmed_key || result.openevidence_key) {
    document.getElementById('pubmed-key').value = result.pubmed_key || result.openevidence_key;
  }
  disabledRules = Array.isArray(result.disabledRules) ? result.disabledRules : [];
  renderDisabledRules();
  
  updateUI(provider);
});

function parseRuleInput(type) {
  const raw = disabledUrlInput.value.trim();
  if (!raw) throw new Error('Enter a website or webpage address.');

  let url;
  try {
    url = new URL(/^[a-z][a-z\d+.-]*:\/\//i.test(raw) ? raw : `https://${raw}`);
  } catch (_) {
    throw new Error('Enter a valid website or webpage address.');
  }

  if (!['http:', 'https:'].includes(url.protocol) || !url.hostname) {
    throw new Error('Only HTTP and HTTPS addresses are supported.');
  }

  if (type === 'site') {
    return { type, value: url.hostname.toLowerCase().replace(/^www\./, '') };
  }

  url.hash = '';
  return { type, value: url.href };
}

function renderDisabledRules() {
  disabledList.replaceChildren();

  if (!disabledRules.length) {
    const empty = document.createElement('div');
    empty.className = 'empty-list';
    empty.textContent = 'AiFly is enabled on all websites.';
    disabledList.appendChild(empty);
    return;
  }

  disabledRules.forEach((rule, index) => {
    const row = document.createElement('div');
    row.className = 'disabled-rule';

    const type = document.createElement('span');
    type.className = 'rule-type';
    type.textContent = rule.type === 'site' ? 'Website' : 'Webpage';

    const value = document.createElement('span');
    value.className = 'rule-value';
    value.textContent = rule.value;

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn-remove-rule';
    remove.textContent = 'Remove';
    remove.addEventListener('click', () => {
      disabledRules.splice(index, 1);
      persistDisabledRules('Rule removed. Refresh an open page to apply the change.');
    });

    row.append(type, value, remove);
    disabledList.appendChild(row);
  });
}

function persistDisabledRules(message) {
  chrome.storage.sync.set({ disabledRules }, () => {
    renderDisabledRules();
    disabledUrlStatus.textContent = message;
    disabledUrlStatus.className = 'test-status success';
  });
}

function addDisabledRule(type) {
  try {
    const rule = parseRuleInput(type);
    const duplicate = disabledRules.some(item => item.type === rule.type && item.value === rule.value);
    if (duplicate) throw new Error('That rule is already in the list.');

    disabledRules.push(rule);
    disabledRules.sort((a, b) => a.type.localeCompare(b.type) || a.value.localeCompare(b.value));
    disabledUrlInput.value = '';
    persistDisabledRules('Rule added. Refresh an open page to disable AiFly there.');
  } catch (error) {
    disabledUrlStatus.textContent = error.message;
    disabledUrlStatus.className = 'test-status error';
  }
}

document.getElementById('add-website').addEventListener('click', () => addDisabledRule('site'));
document.getElementById('add-webpage').addEventListener('click', () => addDisabledRule('page'));
disabledUrlInput.addEventListener('keydown', (event) => {
  if (event.key === 'Enter') {
    event.preventDefault();
    addDisabledRule('site');
  }
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
    pubmedSection.style.display = 'none';
  } else if (provider === 'gemini') {
    chatgptSection.style.display = 'none';
    geminiSection.style.display = 'block';
    pubmedSection.style.display = 'none';
  } else if (provider === 'pubmed') {
    chatgptSection.style.display = 'none';
    geminiSection.style.display = 'none';
    pubmedSection.style.display = 'block';
  }
}

// Save
document.getElementById('save').addEventListener('click', () => {
  const provider = providerInput.value;
  const chatgptKey = document.getElementById('chatgpt-key').value.trim();
  const geminiKey = document.getElementById('gemini-key').value.trim();
  const pubmedKey = document.getElementById('pubmed-key').value.trim();
  const shortcut = shortcutInput.value.trim() || 'Alt+Space';

  if (provider === 'chatgpt' && !chatgptKey) {
    showStatus('Please enter your ChatGPT API key', 'error');
    return;
  }

  if (provider === 'gemini' && !geminiKey) {
    showStatus('Please enter your Gemini API key', 'error');
    return;
  }

  chrome.storage.sync.set({
    provider,
    chatgpt_key: chatgptKey,
    gemini_key: geminiKey,
    pubmed_key: pubmedKey,
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
  document.getElementById('pubmed-key').value = '';
  shortcutInput.value = 'Alt+Space';
  showStatus('Fields cleared', 'success');
  setTimeout(() => statusDiv.classList.remove('success'), 2000);
});

function showStatus(message, type) {
  statusDiv.textContent = message;
  statusDiv.className = `status ${type}`;
}
