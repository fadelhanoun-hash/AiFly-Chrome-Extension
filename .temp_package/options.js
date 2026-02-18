// Options page script
const providerBtns = document.querySelectorAll('[data-provider]');
const chatgptSection = document.getElementById('chatgpt-section');
const geminiSection = document.getElementById('gemini-section');
const providerInput = document.getElementById('provider');
const statusDiv = document.getElementById('status');
const shortcutInput = document.getElementById('shortcut');

// Load settings from sync storage (persists permanently and across devices)
chrome.storage.sync.get(['provider', 'chatgpt_key', 'gemini_key', 'shortcut'], (result) => {
  const provider = result.provider || 'chatgpt';
  providerInput.value = provider;

  shortcutInput.value = result.shortcut || 'Alt+Space';
  
  if (result.chatgpt_key) {
    document.getElementById('chatgpt-key').value = result.chatgpt_key;
  }
  if (result.gemini_key) {
    document.getElementById('gemini-key').value = result.gemini_key;
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
  } else {
    chatgptSection.style.display = 'none';
    geminiSection.style.display = 'block';
  }
}

// Save
document.getElementById('save').addEventListener('click', () => {
  const provider = providerInput.value;
  const chatgptKey = document.getElementById('chatgpt-key').value.trim();
  const geminiKey = document.getElementById('gemini-key').value.trim();
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
  shortcutInput.value = 'Alt+Space';
  showStatus('Fields cleared', 'success');
  setTimeout(() => statusDiv.classList.remove('success'), 2000);
});

function showStatus(message, type) {
  statusDiv.textContent = message;
  statusDiv.className = `status ${type}`;
}
