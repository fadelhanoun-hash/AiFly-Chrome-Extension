// Content script for configurable hotkey
let messengerWindow = null;
let shortcutConfig = {
  alt: true,
  ctrl: false,
  shift: false,
  meta: false,
  key: 'Space'
};

function parseShortcutString(value) {
  const config = { alt: false, ctrl: false, shift: false, meta: false, key: '' };
  if (!value || typeof value !== 'string') return { ...shortcutConfig };

  const parts = value.split('+').map(part => part.trim()).filter(Boolean);
  parts.forEach(part => {
    const lower = part.toLowerCase();
    if (lower === 'alt' || lower === 'option') {
      config.alt = true;
    } else if (lower === 'ctrl' || lower === 'control') {
      config.ctrl = true;
    } else if (lower === 'shift') {
      config.shift = true;
    } else if (lower === 'meta' || lower === 'cmd' || lower === 'command' || lower === 'win' || lower === 'windows') {
      config.meta = true;
    } else {
      config.key = part;
    }
  });

  if (!config.key) config.key = 'Space';
  return config;
}

function matchesShortcut(event, config) {
  if (!config) return false;
  const key = (config.key || '').toLowerCase();
  const eventKey = (event.key || '').toLowerCase();
  const eventCode = (event.code || '').toLowerCase();

  const isSpace = key === 'space' && (eventKey === ' ' || eventKey === 'spacebar' || eventCode === 'space');
  const keyMatches = isSpace || eventKey === key || eventCode === key;

  return keyMatches &&
    event.altKey === !!config.alt &&
    event.ctrlKey === !!config.ctrl &&
    event.shiftKey === !!config.shift &&
    event.metaKey === !!config.meta;
}

// Wait for DOM to be ready
function init() {
  // Ensure document has head and body on blank pages
  if (!document.head) {
    document.documentElement.appendChild(document.createElement('head'));
  }
  if (!document.body) {
    document.documentElement.appendChild(document.createElement('body'));
  }

  // Inject styles inline to avoid CSS loading issues
  const style = document.createElement('style');
  style.textContent = `
    #ai-assistant-messenger {
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      z-index: 999999;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      width: 100%;
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
      background: rgba(0, 0, 0, 0.3);
    }

    #ai-assistant-window {
      width: 650px;
      height: 600px;
      background: white;
      border-radius: 12px;
      display: flex;
      flex-direction: column;
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.15);
      overflow: hidden;
      position: relative;
    }

    .resize-handle {
      position: absolute;
      z-index: 10;
      pointer-events: auto;
      background: transparent;
    }

    .resize-right {
      right: 0;
      top: 0;
      bottom: 0;
      width: 8px;
      cursor: ew-resize;
    }

    .resize-bottom {
      left: 0;
      right: 0;
      bottom: 0;
      height: 8px;
      cursor: ns-resize;
    }

    .resize-corner {
      right: 0;
      bottom: 0;
      width: 16px;
      height: 16px;
      cursor: nwse-resize;
      background: transparent;
      border-radius: 0 0 12px 0;
    }

    .resize-corner:hover {
      background: rgba(0, 123, 255, 0.2);
    }

    #ai-assistant-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 16px 20px;
      background: #f8f9fa;
      border-bottom: 1px solid #e9ecef;
    }

    #ai-assistant-title {
      font-weight: 600;
      font-size: 15px;
      color: #212529;
    }

    #ai-assistant-controls {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    #ai-assistant-toggle {
      display: flex;
    }

    #ai-assistant-font-controls {
      display: flex;
      gap: 4px;
    }

    .font-btn {
      background: #f8f9fa;
      border: none;
      color: #495057;
      padding: 4px 10px;
      border-radius: 6px;
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
      min-width: 36px;
    }

    .font-btn:hover {
      background: #e9ecef;
    }

    .font-btn:active {
      background: #dee2e6;
    }

    .provider-toggle {
      background: #f8f9fa;
      border: none;
      color: #495057;
      padding: 4px 10px;
      border-radius: 6px;
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
      white-space: nowrap;
      min-width: 60px;
    }

    .provider-toggle:hover {
      background: #e9ecef;
    }

    .provider-toggle:active {
      background: #dee2e6;
    }

    .provider-toggle.active {
      background: #dee2e6;
      color: #495057;
    }

    .clear-btn {
      background: #f8f9fa;
      border: none;
      color: #495057;
      padding: 4px 10px;
      border-radius: 6px;
      font-size: 12px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
      white-space: nowrap;
      min-width: 50px;
    }

    .clear-btn:hover {
      background: #e9ecef;
    }

    .clear-btn:active {
      background: #dee2e6;
    }

    #ai-assistant-chat {
      flex: 1;
      overflow-y: auto;
      padding: 16px;
      display: flex;
      flex-direction: column;
      gap: 12px;
      background: white;
    }

    .ai-assistant-message {
      padding: 10px 14px;
      border-radius: 8px;
      line-height: 1.5;
      word-wrap: break-word;
      max-width: 85%;
    }

    .user-message {
      background: #007bff;
      color: white;
      align-self: flex-end;
      border-radius: 8px 8px 2px 8px;
    }

    .ai-message {
      background: #f1f3f5;
      color: #212529;
      align-self: flex-start;
      border-radius: 8px 8px 8px 2px;
      display: flex;
      flex-direction: column;
      padding: 0;
    }

    .message-content {
      padding: 10px 14px 8px 14px;
      font-size: inherit;
    }

    .bold-popup {
      position: fixed;
      z-index: 1000000;
      display: none;
      align-items: center;
      gap: 6px;
      padding: 8px 10px;
      background: #ffffff;
      border: 1px solid #dee2e6;
      border-radius: 8px;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
      font-size: 12px;
      color: #495057;
      backdrop-filter: blur(4px);
    }

    .bold-popup.visible {
      display: flex;
      animation: popupSlideUp 0.2s ease-out;
    }

    @keyframes popupSlideUp {
      from {
        opacity: 0;
        transform: translateY(4px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    .bold-popup-btn {
      background: #f8f9fa;
      border: none;
      color: #495057;
      padding: 6px 10px;
      border-radius: 6px;
      font-size: 12px;
      cursor: pointer;
      transition: all 0.2s ease;
      white-space: nowrap;
      font-weight: 500;
    }

    .bold-popup-btn:hover {
      background: #007bff;
      color: white;
    }

    .bold-popup-btn:active {
      background: #0056b3;
      transform: scale(0.98);
    }

    strong.ai-bold {
      font-weight: 600;
      color: #007bff;
      cursor: pointer;
      transition: all 0.15s ease;
      padding: 1px 3px;
      border-radius: 3px;
    }

    strong.ai-bold:hover {
      background-color: rgba(0, 123, 255, 0.1);
    }

    .message-content * {
      font-size: inherit;
    }

    .message-actions {
      display: flex;
      gap: 8px;
      padding: 8px 10px;
      background: transparent;
    }

    .action-btn {
      background: #f1f3f5;
      border: 1px solid #dee2e6;
      border-radius: 6px;
      padding: 5px 12px;
      font-size: 11px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s ease;
      color: #495057;
      text-transform: uppercase;
      letter-spacing: 0.3px;
    }

    .action-btn:hover {
      background: #007bff;
      border-color: #007bff;
      color: white;
      transform: translateY(-1px);
    }

    .action-btn:active {
      transform: translateY(0);
    }

    .ai-message strong {
      color: #212529;
      font-weight: 600;
    }

    .ai-message mark {
      background: linear-gradient(120deg, #ffeaa7 0%, #fdcb6e 100%);
      color: #2d3436;
      padding: 3px 8px;
      border-radius: 8px;
      font-weight: 500;
      box-shadow: 0 2px 4px rgba(253, 203, 110, 0.3);
    }

    .ai-table {
      width: 100%;
      border-collapse: collapse;
      margin: 8px 0;
      font-size: inherit;
      background: white;
      border-radius: 6px;
      overflow: hidden;
    }

    .ai-table td {
      padding: 8px 12px;
      border: 1px solid #e9ecef;
    }

    .ai-table tr:first-child td {
      background: #f8f9fa;
      font-weight: 600;
    }

    .ai-table tr:hover {
      background: #f8f9fa;
    }

    .bullet-point {
      display: block;
      margin: 4px 0;
      padding-left: 18px;
      text-indent: -12px;
      line-height: 1.5;
    }

    .loading {
      font-style: italic;
      color: #6c757d;
    }

    #ai-assistant-input-area {
      display: flex;
      gap: 8px;
      padding: 12px 16px;
      background: white;
    }

    #ai-assistant-input-wrapper {
      flex: 1;
      position: relative;
      display: flex;
      align-items: center;
    }

    #ai-assistant-input {
      flex: 1;
      border: 1px solid #cbd5e1;
      border-radius: 6px;
      padding: 8px 12px 8px 12px;
      font-size: 14px;
      outline: none;
      transition: all 0.2s ease;
      font-family: inherit;
      background: #f8fafc;
      padding-right: 120px;
    }

    #ai-assistant-input:focus {
      border-color: #93c5fd;
      box-shadow: 0 0 0 1pt rgba(147, 197, 253, 0.3);
    }

    .input-action-btn {
      position: absolute;
      right: 8px;
      background: none;
      border: none;
      color: #007bff;
      cursor: pointer;
      font-size: 13px;
      font-weight: 500;
      padding: 4px 8px;
      border-radius: 4px;
      transition: all 0.2s ease;
      white-space: nowrap;
    }

    .input-action-btn:hover {
      background: rgba(0, 123, 255, 0.1);
      color: #005a87;
    }

    .input-action-btn:active {
      transform: scale(0.95);
    }

    #ai-assistant-backspace {
      position: absolute;
      right: 93px;
      background: none;
      border: none;
      color: #adb5bd;
      cursor: pointer;
      font-size: 20px;
      padding: 0;
      transition: opacity 0.2s ease;
      display: none;
    }

    #ai-assistant-backspace.visible {
      display: block;
    }

    #ai-assistant-backspace:hover {
      opacity: 0.6;
    }

    #ai-assistant-backspace:active {
      opacity: 0.4;
    }

    #ai-assistant-suggestions {
      display: flex;
      gap: 6px;
      padding: 8px 16px 4px 16px;
      background: white;
      flex-wrap: wrap;
    }

    .suggestion-btn {
      background: #f8fafc;
      border: none;
      border-radius: 16px;
      padding: 6px 12px;
      font-size: 12px;
      color: #475569;
      cursor: pointer;
      transition: all 0.2s ease;
      white-space: nowrap;
    }

    .suggestion-btn:hover {
      background: #e2e8f0;
      color: #1e293b;
    }

    #ai-assistant-input:focus {
      border-color: #93c5fd;
      background: #f1f5f9;
      box-shadow: 0 0 0 2px rgba(147, 197, 253, 0.1);
    }

    #ai-assistant-send {
      background: #007bff;
      color: white;
      border: none;
      border-radius: 6px;
      padding: 8px 16px;
      font-size: 14px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    #ai-assistant-send:hover {
      background: #0056b3;
    }

    #ai-assistant-send:active {
      transform: scale(0.98);
    }

    #ai-assistant-chat::-webkit-scrollbar {
      width: 6px;
    }

    #ai-assistant-chat::-webkit-scrollbar-track {
      background: transparent;
    }

    #ai-assistant-chat::-webkit-scrollbar-thumb {
      background: #dee2e6;
      border-radius: 3px;
    }

    #ai-assistant-chat::-webkit-scrollbar-thumb:hover {
      background: #adb5bd;
    }

    @media (max-width: 600px) {
      #ai-assistant-window {
        width: 90vw;
        height: 80vh;
        max-width: 450px;
        max-height: 600px;
      }

      .ai-assistant-message {
        max-width: 90%;
      }
    }
  `;
  if (document.head) {
    document.head.appendChild(style);
  }

  chrome.storage.sync.get('shortcut', (result) => {
    shortcutConfig = parseShortcutString(result.shortcut || 'Alt+Space');
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'sync' || !changes.shortcut) return;
    shortcutConfig = parseShortcutString(changes.shortcut.newValue || 'Alt+Space');
  });

  const handleGlobalKeydown = (e) => {
    // Configurable hotkey
    if (matchesShortcut(e, shortcutConfig)) {
      e.preventDefault();
      toggleMessenger();
      return;
    }
    
    // Escape to close
    if (e.key === 'Escape' && messengerWindow) {
      closeMessenger();
    }
  };

  document.addEventListener('keydown', handleGlobalKeydown, true);
}

// Initialize when DOM is ready or after a short delay for blank tabs
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  // Use setTimeout to work with blank pages that may still be initializing
  setTimeout(init, 100);
}

// Debug - let user know script is active
console.log('✓ AI Assistant content script loaded');

function toggleMessenger() {
  if (messengerWindow && messengerWindow.parentElement) {
    closeMessenger();
  } else {
    createMessenger();
  }
}

function createMessenger() {
  // Ensure document has a body
  if (!document.body) {
    document.documentElement.appendChild(document.createElement('body'));
  }

  // Remove existing window if any
  const existing = document.getElementById('ai-assistant-messenger');
  if (existing) existing.remove();

  // Create container
  const container = document.createElement('div');
  container.id = 'ai-assistant-messenger';
  container.innerHTML = `
    <div id="ai-assistant-window">
      <div id="ai-assistant-header">
        <span id="ai-assistant-title">AI Assistant</span>
        <div id="ai-assistant-controls">
          <button id="clear-chat-btn" class="clear-btn" title="Clear chat history">Clear</button>
          <button id="medical-toggle-btn" class="provider-toggle" title="Toggle medical search mode">Medical</button>
          <div id="ai-assistant-toggle">
            <button id="ai-assistant-provider-btn" class="provider-toggle">ChatGPT</button>
          </div>
          <div id="ai-assistant-font-controls">
            <button id="font-decrease" class="font-btn" title="Decrease font size">A-</button>
            <button id="font-increase" class="font-btn" title="Increase font size">A+</button>
          </div>
        </div>
      </div>
      <div id="ai-assistant-chat"></div>
      <div id="ai-assistant-suggestions"></div>
      <div id="ai-assistant-input-area">
        <div id="ai-assistant-input-wrapper">
          <input type="text" id="ai-assistant-input" placeholder="Ask something..." />
          <button id="ai-assistant-backspace" title="Clear input" class="input-action-btn">⌫</button>
          <button id="ai-assistant-clipboard" title="Paste from clipboard" class="input-action-btn">Clipboard</button>
        </div>
        <button id="ai-assistant-send">Send</button>
      </div>
      <div class="resize-handle resize-right"></div>
      <div class="resize-handle resize-bottom"></div>
      <div class="resize-handle resize-corner"></div>
    </div>
    <div id="ai-assistant-bold-popup" class="bold-popup" role="menu" aria-hidden="true">
      <button id="bold-popup-copy" class="bold-popup-btn" type="button">Copy</button>
      <button id="bold-popup-followup" class="bold-popup-btn" type="button">Follow-up</button>
    </div>
  `;

  document.body.appendChild(container);
  messengerWindow = container;

  // Load chat history
  loadChatHistory();

  // Load current provider and medical mode from sync storage
  chrome.storage.sync.get(['provider', 'medicalMode'], (result) => {
    const provider = result.provider || 'chatgpt';
    updateProviderButton(provider);
    
    const medicalMode = result.medicalMode || false;
    updateMedicalButton(medicalMode);
  });

  // Event listeners
  document.getElementById('ai-assistant-send').addEventListener('click', sendMessage);
  document.getElementById('ai-assistant-input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') sendMessage();
  });
  document.getElementById('ai-assistant-provider-btn').addEventListener('click', toggleProvider);
  document.getElementById('clear-chat-btn').addEventListener('click', clearChat);
  document.getElementById('medical-toggle-btn').addEventListener('click', toggleMedicalMode);
  
  // Input change handler to show/hide backspace button
  const input = document.getElementById('ai-assistant-input');
  const backspaceBtn = document.getElementById('ai-assistant-backspace');
  const chatDiv = document.getElementById('ai-assistant-chat');
  const boldPopup = document.getElementById('ai-assistant-bold-popup');
  const boldCopyBtn = document.getElementById('bold-popup-copy');
  const boldFollowupBtn = document.getElementById('bold-popup-followup');
  let activeBoldText = '';
  let boldHideTimeout = null;
  
  input.addEventListener('input', () => {
    if (input.value.trim()) {
      backspaceBtn.classList.add('visible');
    } else {
      backspaceBtn.classList.remove('visible');
    }
  });
  
  // Backspace button handler
  backspaceBtn.addEventListener('click', () => {
    input.value = '';
    backspaceBtn.classList.remove('visible');
    input.focus();
  });

  const hideBoldPopup = () => {
    if (!boldPopup) return;
    boldPopup.classList.remove('visible');
    boldPopup.setAttribute('aria-hidden', 'true');
  };

  const showBoldPopup = (target) => {
    if (!boldPopup || !target) return;
    
    // Extract text content - handle both Element and selection rect objects
    if (target.textContent !== undefined) {
      activeBoldText = target.textContent.trim();
    }
    if (!activeBoldText) return;

    boldPopup.classList.add('visible');
    boldPopup.setAttribute('aria-hidden', 'false');
    boldPopup.style.visibility = 'hidden';

    // Get position for popup
    let rect;
    if (target.getBoundingClientRect) {
      rect = target.getBoundingClientRect();
    } else {
      rect = target;
    }
    
    const popupWidth = boldPopup.offsetWidth;
    let left = rect.left || rect.left === 0 ? rect.left : 0;

    if (left + popupWidth > window.innerWidth - 8) {
      left = window.innerWidth - popupWidth - 8;
    }
    if (left < 8) left = 8;

    boldPopup.style.left = `${left}px`;
    boldPopup.style.top = `${Math.min((rect.bottom || window.innerHeight) + 6, window.innerHeight - 8)}px`;
    boldPopup.style.visibility = 'visible';
  };

  chatDiv.addEventListener('mouseover', (e) => {
    const bold = e.target.closest('strong.ai-bold');
    if (!bold) return;
    if (boldHideTimeout) {
      clearTimeout(boldHideTimeout);
      boldHideTimeout = null;
    }
    showBoldPopup(bold);
  });

  chatDiv.addEventListener('mouseout', (e) => {
    const bold = e.target.closest('strong.ai-bold');
    if (!bold) return;
    const related = e.relatedTarget;
    if (related && boldPopup.contains(related)) return;
    boldHideTimeout = setTimeout(hideBoldPopup, 120);
  });

  boldPopup.addEventListener('mouseenter', () => {
    if (boldHideTimeout) {
      clearTimeout(boldHideTimeout);
      boldHideTimeout = null;
    }
  });

  boldPopup.addEventListener('mouseleave', () => {
    hideBoldPopup();
  });

  chatDiv.addEventListener('scroll', hideBoldPopup);
  document.addEventListener('mouseup', handleTextSelection);
  document.addEventListener('selectionchange', handleTextSelection);

  boldCopyBtn.addEventListener('click', () => {
    if (!activeBoldText) return;
    navigator.clipboard.writeText(activeBoldText);
  });

  boldFollowupBtn.addEventListener('click', () => {
    if (!activeBoldText) return;
    input.value = `Follow-up: ${activeBoldText}`;
    backspaceBtn.classList.add('visible');
    input.focus();
    hideBoldPopup();
  });

  // Handle text selection in chat
  function handleTextSelection() {
    const selection = window.getSelection();
    const selectedText = selection.toString().trim();
    
    if (!selectedText) {
      hideBoldPopup();
      return;
    }
    
    // Check if selection is within chat area
    const range = selection.getRangeAt(0);
    const isInChat = chatDiv.contains(range.commonAncestorContainer);
    
    if (isInChat) {
      activeBoldText = selectedText;
      showBoldPopup(getSelectionRect());
    }
  }

  function getSelectionRect() {
    const selection = window.getSelection();
    if (selection.rangeCount === 0) return null;
    const range = selection.getRangeAt(0);
    const rect = range.getBoundingClientRect();
    return {
      left: rect.left,
      top: rect.top,
      bottom: rect.bottom,
      getBoundingClientRect: () => rect
    };
  }
  
  // Clipboard button handler
  document.getElementById('ai-assistant-clipboard').addEventListener('click', async () => {
    try {
      const text = await navigator.clipboard.readText();
      input.value = text;
      // Show backspace button if there's content
      if (text.trim()) {
        backspaceBtn.classList.add('visible');
      }
      input.focus();
    } catch (err) {
      console.error('Failed to read clipboard:', err);
      // Fallback: show error message
      alert('Unable to access clipboard. Please paste manually.');
    }
  });
  
  // Font size controls - load saved size
  chrome.storage.sync.get('fontSize', (result) => {
    const savedSize = result.fontSize || 14;
    document.getElementById('ai-assistant-chat').style.fontSize = savedSize + 'px';
  });
  
  document.getElementById('font-decrease').addEventListener('click', () => {
    const chatDiv = document.getElementById('ai-assistant-chat');
    const currentSize = parseInt(chatDiv.style.fontSize) || 14;
    if (currentSize > 10) {
      const newSize = currentSize - 2;
      chatDiv.style.fontSize = newSize + 'px';
      chrome.storage.sync.set({ fontSize: newSize });
    }
  });
  document.getElementById('font-increase').addEventListener('click', () => {
    const chatDiv = document.getElementById('ai-assistant-chat');
    const currentSize = parseInt(chatDiv.style.fontSize) || 14;
    if (currentSize < 24) {
      const newSize = currentSize + 2;
      chatDiv.style.fontSize = newSize + 'px';
      chrome.storage.sync.set({ fontSize: newSize });
    }
  });

  // Delegate message action buttons
  document.getElementById('ai-assistant-chat').addEventListener('click', (e) => {
    const btn = e.target.closest('.action-btn');
    if (!btn) return;
    
    if (btn.classList.contains('copy-btn')) {
      const messageEl = btn.closest('.ai-message');
      const contentEl = messageEl.querySelector('.message-content');
      let messageText = contentEl.innerText;
      // Remove leading and trailing white lines
      messageText = messageText.replace(/^\s*\n+|\n+\s*$/g, '').trim();
      navigator.clipboard.writeText(messageText).then(() => {
        const originalText = btn.textContent;
        btn.textContent = 'Copied!';
        setTimeout(() => btn.textContent = originalText, 1500);
      });
    } else if (btn.classList.contains('copy-table-btn')) {
      const messageEl = btn.closest('.ai-message');
      const contentEl = messageEl.querySelector('.message-content');
      const table = contentEl.querySelector('table.ai-table');
      
      if (table) {
        // Extract table data in tab-separated format (TSV)
        const rows = Array.from(table.querySelectorAll('tr'));
        const textToCopy = rows.map(row => {
          const cells = Array.from(row.querySelectorAll('td'));
          return cells.map(cell => cell.innerText.trim()).join('\t');
        }).join('\n');
        
        navigator.clipboard.writeText(textToCopy).then(() => {
          const originalText = btn.textContent;
          btn.textContent = 'Copied!';
          setTimeout(() => btn.textContent = originalText, 1500);
        });
      }
    } else if (btn.classList.contains('followup-btn')) {
      const input = document.getElementById('ai-assistant-input');
      input.focus();
      input.placeholder = 'Ask a follow-up question...';
      setTimeout(() => input.placeholder = 'Ask something...', 3000);
    }
  });

  // Close when clicking outside the window
  container.addEventListener('click', (e) => {
    // Don't close if clicking on a resize handle
    if (e.target.classList.contains('resize-handle')) {
      e.preventDefault();
      e.stopPropagation();
      return;
    }
    if (e.target === container && !isResizing) {
      closeMessenger();
    }
  });

  // Resize functionality
  const windowEl = document.getElementById('ai-assistant-window');
  let isResizing = false;
  let resizeType = null;
  let startX, startY, startWidth, startHeight;

  // Load saved dimensions
  chrome.storage.sync.get(['windowWidth', 'windowHeight'], (result) => {
    if (result.windowWidth) windowEl.style.width = result.windowWidth + 'px';
    if (result.windowHeight) windowEl.style.height = result.windowHeight + 'px';
  });

  document.querySelectorAll('.resize-handle').forEach(handle => {
    handle.addEventListener('mousedown', (e) => {
      isResizing = true;
      resizeType = handle.classList.contains('resize-right') ? 'right' :
                   handle.classList.contains('resize-bottom') ? 'bottom' : 'corner';
      startX = e.clientX;
      startY = e.clientY;
      startWidth = windowEl.offsetWidth;
      startHeight = windowEl.offsetHeight;
      e.preventDefault();
      e.stopPropagation();
    });
  });

  document.addEventListener('mousemove', (e) => {
    if (!isResizing) return;

    if (resizeType === 'right' || resizeType === 'corner') {
      const newWidth = startWidth + (e.clientX - startX);
      if (newWidth >= 400 && newWidth <= 1000) {
        windowEl.style.width = newWidth + 'px';
      }
    }
    if (resizeType === 'bottom' || resizeType === 'corner') {
      const newHeight = startHeight + (e.clientY - startY);
      if (newHeight >= 400 && newHeight <= 800) {
        windowEl.style.height = newHeight + 'px';
      }
    }
  });

  document.addEventListener('mouseup', () => {
    if (isResizing) {
      isResizing = false;
      // Save dimensions
      chrome.storage.sync.set({
        windowWidth: windowEl.offsetWidth,
        windowHeight: windowEl.offsetHeight
      });
    }
  });

  // Focus input with delay to ensure it works
  setTimeout(() => {
    const input = document.getElementById('ai-assistant-input');
    if (input) {
      input.focus();
      input.select();
    }
  }, 100);
}

function clearChat() {
  if (confirm('Clear all chat history?')) {
    chrome.storage.local.set({ chatHistory: [] }, () => {
      const chatDiv = document.getElementById('ai-assistant-chat');
      chatDiv.innerHTML = '';
    });
  }
}

function updateProviderButton(provider) {
  const btn = document.getElementById('ai-assistant-provider-btn');
  if (btn) {
    btn.textContent = provider === 'chatgpt' ? 'ChatGPT' : 'Gemini';
    btn.setAttribute('data-provider', provider);
  }
}

function updateMedicalButton(isActive) {
  const btn = document.getElementById('medical-toggle-btn');
  if (btn) {
    if (isActive) {
      btn.classList.add('active');
    } else {
      btn.classList.remove('active');
    }
  }
}

function toggleMedicalMode() {
  chrome.storage.sync.get('medicalMode', (result) => {
    const currentMode = result.medicalMode || false;
    const newMode = !currentMode;
    
    chrome.storage.sync.set({ medicalMode: newMode }, () => {
      updateMedicalButton(newMode);
      
      // Show notification
      const btn = document.getElementById('medical-toggle-btn');
      const originalText = btn.textContent;
      btn.textContent = newMode ? '✓ Medical ON' : '✓ Medical OFF';
      setTimeout(() => {
        btn.textContent = 'Medical';
      }, 1500);
    });
  });
}

function toggleProvider() {
  chrome.storage.sync.get('provider', (result) => {
    const currentProvider = result.provider || 'chatgpt';
    const newProvider = currentProvider === 'chatgpt' ? 'gemini' : 'chatgpt';
    
    chrome.storage.sync.set({ provider: newProvider }, () => {
      updateProviderButton(newProvider);
      
      // Show notification
      const btn = document.getElementById('ai-assistant-provider-btn');
      const originalText = btn.textContent;
      btn.textContent = '✓ Switched!';
      setTimeout(() => {
        btn.textContent = newProvider === 'chatgpt' ? 'ChatGPT' : 'Gemini';
      }, 1000);
    });
  });
}

function closeMessenger() {
  if (messengerWindow) {
    messengerWindow.remove();
    messengerWindow = null;
  }
}

async function sendMessage() {
  const input = document.getElementById('ai-assistant-input');
  const message = input.value.trim();

  if (!message) return;

  const chatDiv = document.getElementById('ai-assistant-chat');

  // Add user message
  const userMsg = document.createElement('div');
  userMsg.className = 'ai-assistant-message user-message';
  userMsg.textContent = message;
  chatDiv.appendChild(userMsg);

  // Save to history
  await saveChatMessage('user', message);

  input.value = '';
  chatDiv.scrollTop = chatDiv.scrollHeight;

  // Show loading
  const loadingMsg = document.createElement('div');
  loadingMsg.className = 'ai-assistant-message ai-message loading';
  loadingMsg.textContent = 'Thinking...';
  chatDiv.appendChild(loadingMsg);
  chatDiv.scrollTop = chatDiv.scrollHeight;

  try {
    // Get conversation history for context and medical mode
    const data = await chrome.storage.local.get('chatHistory');
    const history = data.chatHistory || [];
    
    // Get medical mode setting
    const syncData = await chrome.storage.sync.get('medicalMode');
    const medicalMode = syncData.medicalMode || false;
    
    // Prepend medical context if enabled
    let contextMessage = message;
    if (medicalMode) {
      contextMessage = 'Medical query (provide medication doses, frequencies, diagnosis criteria, and treatment protocols): ' + message;
    }
    
    // Get AI response with conversation context
    const response = await new Promise((resolve, reject) => {
      chrome.runtime.sendMessage(
        { type: 'GET_AI_RESPONSE', message: contextMessage, history },
        (result) => {
          if (result.success) {
            resolve(result.response);
          } else {
            reject(new Error(result.error));
          }
        }
      );
    });

    // Remove loading message
    loadingMsg.remove();

    // Add AI response with formatting
    const aiMsg = document.createElement('div');
    aiMsg.className = 'ai-assistant-message ai-message';
    
    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    contentDiv.innerHTML = formatAIResponse(response);
    
    // Add action buttons container at bottom inside bubble
    const actionsDiv = document.createElement('div');
    actionsDiv.className = 'message-actions';
    
    // Check if response contains a table
    const hasTable = contentDiv.querySelector('table.ai-table');
    
    actionsDiv.innerHTML = `
      <button class="action-btn copy-btn">Copy</button>
      ${hasTable ? '<button class="action-btn copy-table-btn">Copy Table</button>' : ''}
      <button class="action-btn followup-btn">Follow-up</button>
    `;
    
    aiMsg.appendChild(contentDiv);
    aiMsg.appendChild(actionsDiv);
    chatDiv.appendChild(aiMsg);

    // Generate and display suggestions
    generateSuggestions(message, response);

    // Save to history
    await saveChatMessage('assistant', response);
  } catch (error) {
    loadingMsg.textContent = `Error: ${error.message}`;
  }

  chatDiv.scrollTop = chatDiv.scrollHeight;
}

// Common medication names to detect and bold
const MEDICATIONS = [
  'aspirin', 'ibuprofen', 'acetaminophen', 'paracetamol', 'naproxen', 'diclofenac',
  'amoxicillin', 'penicillin', 'azithromycin', 'doxycycline', 'ciprofloxacin',
  'metformin', 'insulin', 'lisinopril', 'atorvastatin', 'amlodipine',
  'sertraline', 'fluoxetine', 'escitalopram', 'paroxetine', 'citalopram',
  'omeprazole', 'ranitidine', 'famotidine', 'cimetidine',
  'loratadine', 'cetirizine', 'fexofenadine', 'chlorpheniramine',
  'diphenhydramine', 'promethazine', 'dextromethorphan',
  'oxycodone', 'morphine', 'codeine', 'hydrocodone', 'tramadol',
  'diazepam', 'alprazolam', 'lorazepam', 'clonazepam',
  'propranolol', 'metoprolol', 'atenolol', 'carvedilol',
  'levothyroxine', 'synthroid', 'warfarin', 'aspirin'
];

function detectAndBoldMedications(text) {
  // Create a regex pattern for medication detection (case-insensitive, word boundaries)
  const medicationRegex = new RegExp(
    `\\b(${MEDICATIONS.join('|')})\\b`,
    'gi'
  );
  
  // Replace medication names with bolded version, but avoid double-bolding
  text = text.replace(/(?<!\*\*)<strong[^>]*class="?ai-bold"?[^>]*>(.*?)<\/strong>(?!\*\*)/gi, '**$1**');
  text = text.replace(
    medicationRegex,
    (match) => {
      // Check if already bolded
      return `**${match}**`;
    }
  );
  
  return text;
}

function formatAIResponse(text) {
  // Remove leading and trailing whitespace/newlines
  text = text.replace(/^\s*\n+|\n+\s*$/g, '').trim();
  
  // Detect and bold medication names
  text = detectAndBoldMedications(text);
  
  // Highlights ==text==
  text = text.replace(/==(.*?)==/g, '<mark>$1</mark>');
  
  // Bold **text** (including auto-detected medications)
  text = text.replace(/\*\*(.*?)\*\*/g, '<strong class="ai-bold">$1</strong>');
  
  // Tables (markdown style)
  text = text.replace(/\|(.+)\|/g, (match) => {
    if (match.includes('---')) {
      return ''; // Skip separator rows
    }
    const cells = match.split('|').filter(cell => cell.trim());
    const cellTags = cells.map(cell => `<td>${cell.trim()}</td>`).join('');
    return `<tr>${cellTags}</tr>`;
  });
  
  // Wrap table rows in table
  if (text.includes('<tr>')) {
    text = text.replace(/(<tr>.*<\/tr>)/gs, '<table class="ai-table">$1</table>');
  }
  
  // Bullet points with proper styling
  text = text.replace(/^[•\-\*]\s+(.*)$/gm, '<span class="bullet-point">→ $1</span>');
  
  // Line breaks
  text = text.replace(/\n/g, '<br>');
  
  // Remove multiple consecutive <br> tags (reduce to max 1)
  text = text.replace(/(<br>\s*){2,}/gi, '<br>');
  
  // Remove any <br> immediately before tables
  text = text.replace(/<br>\s*<table/gi, '<table');
  // Remove any <br> immediately after tables  
  text = text.replace(/<\/table>\s*<br>/gi, '</table>');
  
  return text;
}

async function saveChatMessage(role, content) {
  const data = await chrome.storage.local.get('chatHistory');
  const history = data.chatHistory || [];
  
  history.push({ role, content, timestamp: Date.now() });
  
  // Keep only last 100 messages
  if (history.length > 100) {
    history.shift();
  }
  
  await chrome.storage.local.set({ chatHistory: history });
}

async function loadChatHistory() {
  const data = await chrome.storage.local.get('chatHistory');
  const history = data.chatHistory || [];
  const chatDiv = document.getElementById('ai-assistant-chat');

  history.forEach(msg => {
    if (msg.role === 'assistant') {
      // AI message with proper structure
      const aiMsg = document.createElement('div');
      aiMsg.className = 'ai-assistant-message ai-message';
      
      const contentDiv = document.createElement('div');
      contentDiv.className = 'message-content';
      contentDiv.innerHTML = formatAIResponse(msg.content);
      
      const actionsDiv = document.createElement('div');
      actionsDiv.className = 'message-actions';
      
      // Check if message contains a table
      const hasTable = contentDiv.querySelector('table.ai-table');
      
      actionsDiv.innerHTML = `
        <button class="action-btn copy-btn">Copy</button>
        ${hasTable ? '<button class="action-btn copy-table-btn">Copy Table</button>' : ''}
        <button class="action-btn followup-btn">Follow-up</button>
      `;
      
      aiMsg.appendChild(contentDiv);
      aiMsg.appendChild(actionsDiv);
      chatDiv.appendChild(aiMsg);
    } else {
      // User message
      const userMsg = document.createElement('div');
      userMsg.className = 'ai-assistant-message user-message';
      userMsg.textContent = msg.content;
      chatDiv.appendChild(userMsg);
    }
  });

  chatDiv.scrollTop = chatDiv.scrollHeight;
}

function generateSuggestions(userMessage, aiResponse) {
  const suggestionsDiv = document.getElementById('ai-assistant-suggestions');
  
  // Generate contextual suggestions based on the conversation
  const suggestions = [
    'Tell me more',
    'Explain further',
    'Give an example',
    'What else?'
  ];
  
  suggestionsDiv.innerHTML = suggestions.map(text => 
    `<button class="suggestion-btn">${text}</button>`
  ).join('');
  
  // Add click handlers
  suggestionsDiv.querySelectorAll('.suggestion-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const input = document.getElementById('ai-assistant-input');
      input.value = btn.textContent;
      input.focus();
      document.getElementById('ai-assistant-send').click();
    });
  });
}
