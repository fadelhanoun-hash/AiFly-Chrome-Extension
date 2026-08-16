// Content script for configurable hotkey
let messengerWindow = null;
let selectionPopupVisible = false;
let currentSelectedText = '';
let silentSend = false; // when true, next sendMessage() skips the user bubble
let lastUserRequest = '';
let resendPendingProvider = '';
let followUpContext = ''; // stores AI bubble text when user clicks Follow-up
let activeChatSelectionRange = null;
let inlineFormatShortcutBound = false;
let extensionDisabled = false;
const RESPONSE_FORMAT_GUIDANCE = [
  'Formatting requirements for this response:',
  '- Bold important keywords and critical terms using **bold**.',
  '- Use rounded highlighted text with color when emphasis is helpful, using ==highlighted phrase== where appropriate.',
  '- Keep formatting readable and purposeful; do not over-highlight every sentence.'
].join('\n');
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
      gap: 6px;
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

    .provider-toggle.engine-btn {
      min-width: auto;
      padding: 4px 8px;
      font-size: 11px;
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
      padding: 16px 16px 130px 16px;
      display: flex;
      flex-direction: column;
      gap: 12px;
      background: white;
      scrollbar-width: none;
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
      flex-direction: column;
      align-items: flex-start;
      gap: 8px;
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

    .bold-popup-group {
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .bold-popup-swatch {
      width: 22px;
      height: 22px;
      border-radius: 999px;
      border: 1px solid rgba(0, 0, 0, 0.12);
      cursor: pointer;
      transition: transform 0.15s ease;
    }

    .bold-popup-swatch:hover {
      transform: scale(1.08);
    }

    .bold-popup-swatch:active {
      transform: scale(0.95);
    }

    .bold-popup-shortcut {
      font-size: 10px;
      color: #64748b;
      margin-left: 3px;
    }

    .bold-popup-vdivider {
      width: 1px;
      height: 18px;
      background: #dee2e6;
      margin: 0 2px;
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
      background: transparent !important;
      padding: 0 !important;
      margin: 0 !important;
      align-self: stretch !important;
      max-width: 100% !important;
      border-radius: 0 !important;
      box-shadow: none !important;
    }

    .thinking-bar {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding: 12px 16px 10px 16px;
      border-top: 1px solid #e9ecef;
      background: #f1f3f5;
      border-radius: 12px;
    }

    .thinking-dots {
      display: flex;
      gap: 6px;
      align-items: center;
    }

    .thinking-dots span {
      width: 9px;
      height: 9px;
      border-radius: 50%;
      background: #64748b;
      animation: thinkingBounce 1.2s ease-in-out infinite;
    }

    .thinking-dots span:nth-child(2) { animation-delay: 0.2s; }
    .thinking-dots span:nth-child(3) { animation-delay: 0.4s; }

    @keyframes thinkingBounce {
      0%, 60%, 100% { transform: translateY(0); opacity: 0.4; }
      30%            { transform: translateY(-6px); opacity: 1; }
    }

    .thinking-progress-track {
      width: 100%;
      height: 3px;
      background: #dee2e6;
      border-radius: 99px;
      overflow: hidden;
    }

    .thinking-progress-fill {
      height: 100%;
      width: 30%;
      border-radius: 99px;
      background: linear-gradient(90deg, #93c5fd, #3b82f6, #93c5fd);
      background-size: 200% 100%;
      animation: thinkingSlide 1.4s ease-in-out infinite;
    }

    @keyframes thinkingSlide {
      0%   { transform: translateX(-100%); }
      50%  { transform: translateX(250%); }
      100% { transform: translateX(250%); }
    }

    #ai-bottom-bar {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      background: linear-gradient(to top, white 82%, transparent 100%);
      background-color: transparent;
      border-top: none;
    }

    #ai-assistant-input-area {
      display: flex;
      gap: 8px;
      padding: 8px 16px 14px 16px;
      background: transparent;
    }

    #ai-assistant-input-wrapper {
      flex: 1;
      display: flex;
      align-items: center;
      position: relative;
    }

    #ai-assistant-input {
      flex: 1;
      border: none;
      border-radius: 24px;
      padding: 10px 110px 10px 16px;
      font-size: 14px;
      outline: none;
      transition: background 0.2s ease, box-shadow 0.2s ease;
      font-family: inherit;
      background: #f1f5f9;
      width: 100%;
    }

    #ai-assistant-input:focus {
      background: #e9f0fb;
      box-shadow: 0 0 0 2px rgba(147, 197, 253, 0.45);
    }

    #ai-assistant-input-actions {
      position: absolute;
      right: 10px;
      top: 50%;
      transform: translateY(-50%);
      display: flex;
      align-items: center;
      gap: 4px;
      pointer-events: auto;
    }

    .input-action-btn {
      position: static;
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
      background: none;
      border: none;
      color: #007bff;
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

    #ai-assistant-resend-engine {
      color: #2563eb;
      font-size: 12px;
      font-weight: 600;
      display: none;
    }

    #ai-assistant-resend-engine.visible {
      display: block;
    }

    #ai-assistant-resend-engine:hover {
      background: rgba(37, 99, 235, 0.12);
      color: #1d4ed8;
    }

    #ai-assistant-resend-engine:active {
      transform: scale(0.96);
    }

    #ai-assistant-suggestions {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 8px 16px 4px 16px;
      flex-wrap: nowrap;
      overflow-x: auto;
      scrollbar-width: none;
    }

    #ai-assistant-suggestions::-webkit-scrollbar {
      display: none;
    }

    .suggestion-btn {
      background: #e8f0fb;
      border: none;
      border-radius: 16px;
      padding: 8px 14px;
      font-size: 14px;
      color: #254269;
      cursor: pointer;
      transition: all 0.2s ease;
      white-space: nowrap;
      box-shadow: none;
      flex-shrink: 0;
    }

    .suggestion-btn:hover {
      background: #027bff;
      color: #ffffff;
    }

    /* Image grid bubble */
    .image-grid-bubble {
      max-width: 96% !important;
    }

    .image-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      grid-auto-rows: 140px;
      gap: 6px;
      max-height: 154px;
      overflow-y: auto;
      scrollbar-width: none;
      padding: 4px 10px 10px 10px;
    }

    .image-grid-card {
      position: relative;
      width: 100%;
      height: 100%;
      border-radius: 8px;
      overflow: hidden;
      background: #e2e8f0;
    }

    .image-grid::-webkit-scrollbar {
      display: none;
    }

    .image-grid-item {
      width: 100%;
      height: 100%;
      object-fit: cover;
      border-radius: 6px;
      cursor: pointer;
      display: block;
      transition: transform 0.15s ease, opacity 0.15s ease;
      background: #e2e8f0;
    }

    .image-grid-card:hover .image-grid-item,
    .image-grid-card.active .image-grid-item {
      transform: scale(1.03);
      opacity: 0.88;
    }

    .image-grid-overlay {
      position: absolute;
      left: 50%;
      bottom: 8px;
      transform: translateX(-50%);
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.16s ease;
      z-index: 2;
    }

    .image-grid-card:hover .image-grid-overlay,
    .image-grid-card.active .image-grid-overlay {
      opacity: 1;
      pointer-events: auto;
    }

    .image-grid-overlay-btn {
      border: 1px solid rgba(255, 255, 255, 0.85);
      background: rgba(0, 0, 0, 0.76);
      color: #ffffff;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 600;
      padding: 5px 10px;
      line-height: 1;
      cursor: pointer;
      box-shadow: 0 4px 10px rgba(0, 0, 0, 0.22);
      transition: background 0.16s ease;
      white-space: nowrap;
    }

    .image-grid-overlay-btn:hover {
      background: rgba(0, 0, 0, 0.88);
    }

    #ai-image-preview-dialog {
      position: fixed;
      inset: 0;
      background: rgba(15, 23, 42, 0.74);
      z-index: 1000001;
      display: none;
      align-items: center;
      justify-content: center;
      padding: 20px;
      box-sizing: border-box;
    }

    #ai-image-preview-dialog.visible {
      display: flex;
    }

    .ai-image-preview-shell {
      position: relative;
      max-width: min(92vw, 980px);
      max-height: 90vh;
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
    }

    #ai-image-preview-img {
      max-width: 100%;
      max-height: 90vh;
      border-radius: 10px;
      box-shadow: 0 20px 48px rgba(0, 0, 0, 0.45);
      background: #ffffff;
      object-fit: contain;
      transform-origin: center center;
      transition: transform 0.08s ease;
    }

    #ai-image-preview-close {
      position: absolute;
      top: -12px;
      right: -12px;
      width: 34px;
      height: 34px;
      border-radius: 50%;
      border: none;
      background: #ffffff;
      color: #0f172a;
      font-size: 20px;
      line-height: 1;
      cursor: pointer;
      box-shadow: 0 8px 18px rgba(0, 0, 0, 0.28);
    }

    .ai-image-preview-actions {
      position: absolute;
      left: 50%;
      bottom: 14px;
      transform: translateX(-50%);
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      z-index: 3;
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

    #ai-assistant-send.followup-mode {
      background: #7c3aed;
      box-shadow: 0 2px 10px rgba(0, 0, 0, 0.13), 0 1px 4px rgba(0, 0, 0, 0.07);
    }

    #ai-assistant-send.followup-mode:hover {
      background: #6d28d9;
    }

    #ai-assistant-input.followup-mode {
      box-shadow: 0 0 0 2px rgba(124, 58, 237, 0.35);
      background: #fdf4ff;
    }

    #ai-assistant-chat::-webkit-scrollbar {
      display: none;
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

    /* ── Global selection popup ── */
    #ai-selection-popup {
      position: fixed;
      z-index: 999998;
      display: none;
      align-items: center;
      gap: 5px;
      padding: 7px 10px;
      background: #1e1e2e;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 18px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.35);
      pointer-events: auto;
    }

    #ai-selection-popup.visible {
      display: flex;
      animation: popupSlideUp 0.15s ease-out;
    }

    .sel-btn {
      background: rgba(255, 255, 255, 0.08);
      border: none;
      color: #e2e8f0;
      padding: 6px 12px;
      border-radius: 12px;
      font-size: 13px;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.15s ease, transform 0.1s ease;
      white-space: nowrap;
      display: flex;
      align-items: center;
      gap: 5px;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }

    .sel-btn:active {
      transform: scale(0.96);
    }

    .sel-btn kbd {
      background: rgba(255, 255, 255, 0.1);
      border: 1px solid rgba(255, 255, 255, 0.18);
      border-radius: 5px;
      padding: 1px 5px;
      font-size: 11px;
      font-family: inherit;
      color: #94a3b8;
    }

    .sel-summarize-btn:hover { background: rgba(99, 102, 241, 0.55); }
    .sel-ask-btn:hover       { background: rgba(16, 185, 129, 0.5); }
    .sel-save-btn:hover      { background: rgba(245, 158, 11, 0.5); }

    .sel-divider {
      width: 1px;
      height: 20px;
      background: rgba(255, 255, 255, 0.12);
      margin: 0 2px;
    }
  `;
  if (document.head) {
    document.head.appendChild(style);
  }

  // Create the global text-selection popup (always present in every frame)
  initSelectionPopup();

  // Only set up the main messenger and shortcut listener in the top frame
  if (window !== window.top) return;

  // Top frame: listen for actions bubbled up from child iframes
  window.addEventListener('message', (e) => {
    if (!e.data || e.data.type !== 'AIFLY_ACTION') return;
    const { action, text } = e.data;
    if (action === 'summarize') summarizeSelectedText(text);
    else if (action === 'askAI') askAIAboutSelectedText(text);
    else if (action === 'save') saveSelectedText(text);
  });

  chrome.storage.sync.get('shortcut', (result) => {
    shortcutConfig = parseShortcutString(result.shortcut || 'Alt+Space');
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'sync' || !changes.shortcut) return;
    shortcutConfig = parseShortcutString(changes.shortcut.newValue || 'Alt+Space');
  });

  const handleGlobalKeydown = (e) => {
    if (extensionDisabled) return;
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

    // Selection popup keyboard shortcuts (1 = Summarize, 2 = Ask AI, 4 = Save)
    if (selectionPopupVisible && currentSelectedText) {
      const activeEl = document.activeElement;
      const isTyping = activeEl && (
        activeEl.tagName === 'INPUT' ||
        activeEl.tagName === 'TEXTAREA' ||
        activeEl.isContentEditable
      );
      if (!isTyping) {
        if (e.key === '1') { e.preventDefault(); dispatchSelectionAction('summarize', currentSelectedText); hideSelectionPopup(); return; }
        if (e.key === '2') { e.preventDefault(); dispatchSelectionAction('askAI', currentSelectedText); hideSelectionPopup(); return; }
        if (e.key === '4') { e.preventDefault(); dispatchSelectionAction('save', currentSelectedText); return; }
      }
    }
  };

  document.addEventListener('keydown', handleGlobalKeydown, true);
}

// Listen for OPEN_MESSENGER from background (browser-level shortcut fires from any sidebar)
if (window === window.top) {
  chrome.runtime.onMessage.addListener((request) => {
    if (request.type === 'OPEN_MESSENGER' && !extensionDisabled) toggleMessenger();
  });
}

function isDisabledForUrl(urlString, rules) {
  let url;
  try {
    url = new URL(urlString);
  } catch (_) {
    return false;
  }

  const hostname = url.hostname.toLowerCase().replace(/^www\./, '');
  const pageUrl = `${url.origin}${url.pathname}${url.search}`;

  return (Array.isArray(rules) ? rules : []).some((rule) => {
    if (!rule || !rule.type || !rule.value) return false;
    if (rule.type === 'site') {
      const blockedHost = String(rule.value).toLowerCase().replace(/^www\./, '');
      return hostname === blockedHost || hostname.endsWith(`.${blockedHost}`);
    }
    if (rule.type === 'page') {
      try {
        const blockedUrl = new URL(rule.value);
        return pageUrl === `${blockedUrl.origin}${blockedUrl.pathname}${blockedUrl.search}`;
      } catch (_) {
        return false;
      }
    }
    return false;
  });
}

chrome.storage.sync.get('disabledRules', (result) => {
  extensionDisabled = isDisabledForUrl(window.location.href, result.disabledRules);
  if (extensionDisabled) {
    console.log('AiFly is disabled on this page.');
    return;
  }

  // Initialize when DOM is ready or after a short delay for blank tabs
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    // Use setTimeout to work with blank pages that may still be initializing
    setTimeout(init, 100);
  }

  console.log('✓ AI Assistant content script loaded');
});

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
            <button id="provider-chatgpt" class="provider-toggle engine-btn" data-provider="chatgpt">ChatGPT</button>
            <button id="provider-gemini" class="provider-toggle engine-btn" data-provider="gemini">Gemini</button>
            <button id="provider-pubmed" class="provider-toggle engine-btn" data-provider="pubmed">PubMed</button>
            <button id="provider-jama" class="provider-toggle engine-btn" data-provider="jama">JAMA</button>
          </div>
          <div id="ai-assistant-font-controls">
            <button id="font-decrease" class="font-btn" title="Decrease font size">A-</button>
            <button id="font-increase" class="font-btn" title="Increase font size">A+</button>
          </div>
        </div>
      </div>
      <div id="ai-assistant-chat"></div>
      <div id="ai-bottom-bar">
        <div id="ai-assistant-suggestions">
          <button id="ai-image-search-btn" class="suggestion-btn" title="Search Google Images">Search Image</button>
        </div>
        <div id="ai-assistant-input-area">
          <div id="ai-assistant-input-wrapper">
            <input type="text" id="ai-assistant-input" placeholder="Ask something..." autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" />
            <div id="ai-assistant-input-actions">
              <button id="ai-assistant-backspace" title="Clear input" class="input-action-btn">⌫</button>
              <button id="ai-assistant-resend-engine" title="Send last request to selected engine" class="input-action-btn"></button>
              <button id="ai-assistant-clipboard" title="Paste from clipboard" class="input-action-btn">Clipboard</button>
            </div>
          </div>
          <button id="ai-assistant-send">Send</button>
        </div>
      </div>
      <div class="resize-handle resize-right"></div>
      <div class="resize-handle resize-bottom"></div>
      <div class="resize-handle resize-corner"></div>
    </div>
    <div id="ai-assistant-bold-popup" class="bold-popup" role="menu" aria-hidden="true">
      <div class="bold-popup-group">
        <button id="bold-popup-color-blue" class="bold-popup-swatch" type="button" title="Blue text" style="background:#dbeafe;"></button>
        <button id="bold-popup-color-red" class="bold-popup-swatch" type="button" title="Red text" style="background:#fee2e2;"></button>
        <button id="bold-popup-color-green" class="bold-popup-swatch" type="button" title="Green text" style="background:#dcfce7;"></button>
        <div class="bold-popup-vdivider"></div>
        <button id="bold-popup-highlight-yellow" class="bold-popup-swatch" type="button" title="Yellow highlight" style="background:#fde68a;"></button>
        <button id="bold-popup-highlight-mint" class="bold-popup-swatch" type="button" title="Mint highlight" style="background:#bbf7d0;"></button>
        <button id="bold-popup-highlight-sky" class="bold-popup-swatch" type="button" title="Sky highlight" style="background:#bfdbfe;"></button>
      </div>
      <div class="bold-popup-group">
        <button id="bold-popup-google" class="bold-popup-btn" type="button">Google</button>
        <button id="bold-popup-copy" class="bold-popup-btn" type="button">Copy</button>
        <button id="bold-popup-followup" class="bold-popup-btn" type="button">Follow-up</button>
      </div>
    </div>
  `;

  document.body.appendChild(container);
  messengerWindow = container;

  // Load chat history
  loadChatHistory();

  // Load last user request and pending provider-switch resend state
  loadResendState();

  // Load current provider and medical mode from sync storage
  chrome.storage.sync.get(['provider', 'medicalMode'], (result) => {
    const provider = result.provider || 'chatgpt';
    updateProviderButtons(provider);
    
    const medicalMode = result.medicalMode || false;
    updateMedicalButton(medicalMode);
  });

  // Event listeners
  document.getElementById('ai-assistant-send').addEventListener('click', sendMessage);
  document.getElementById('ai-assistant-input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') sendMessage();
  });
  document.querySelectorAll('.engine-btn').forEach((btn) => {
    btn.addEventListener('click', () => setProvider(btn.getAttribute('data-provider')));
  });
  document.getElementById('clear-chat-btn').addEventListener('click', clearChat);
  document.getElementById('medical-toggle-btn').addEventListener('click', toggleMedicalMode);
  
  // Input change handler to show/hide backspace button
  const input = document.getElementById('ai-assistant-input');
  // Randomize name each mount to prevent Chrome from surfacing prior input suggestions.
  input.setAttribute('name', `aifly-input-${Date.now()}`);
  input.setAttribute('autocomplete', 'off');
  const backspaceBtn = document.getElementById('ai-assistant-backspace');
  const resendEngineBtn = document.getElementById('ai-assistant-resend-engine');
  const chatDiv = document.getElementById('ai-assistant-chat');
  const boldPopup = document.getElementById('ai-assistant-bold-popup');
  const colorBlueBtn = document.getElementById('bold-popup-color-blue');
  const colorRedBtn = document.getElementById('bold-popup-color-red');
  const colorGreenBtn = document.getElementById('bold-popup-color-green');
  const highlightYellowBtn = document.getElementById('bold-popup-highlight-yellow');
  const highlightMintBtn = document.getElementById('bold-popup-highlight-mint');
  const highlightSkyBtn = document.getElementById('bold-popup-highlight-sky');
  const boldGoogleBtn = document.getElementById('bold-popup-google');
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

  resendEngineBtn.addEventListener('click', async () => {
    if (!resendPendingProvider || !lastUserRequest) return;

    input.value = lastUserRequest;
    backspaceBtn.classList.add('visible');
    input.focus();

    // One-time action: hide until provider changes again.
    resendPendingProvider = '';
    await chrome.storage.local.remove('resendPendingProvider');
    updateResendButton();

    sendMessage();
  });

  const hideBoldPopup = () => {
    if (!boldPopup) return;
    boldPopup.classList.remove('visible');
    boldPopup.setAttribute('aria-hidden', 'true');
    activeChatSelectionRange = null;
  };

  const setSelectionRangeFromWindow = () => {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) return false;
    const range = selection.getRangeAt(0);
    if (range.collapsed) return false;
    if (!chatDiv.contains(range.commonAncestorContainer)) return false;
    activeChatSelectionRange = range.cloneRange();
    return true;
  };

  const wrapSelectedContent = (createWrapper) => {
    if (!activeChatSelectionRange) return false;
    const range = activeChatSelectionRange.cloneRange();
    if (range.collapsed) return false;

    const wrapper = createWrapper();
    const extracted = range.extractContents();
    wrapper.appendChild(extracted);
    range.insertNode(wrapper);
    activeChatSelectionRange = null;
    return true;
  };

  const formatSelection = (type) => {
    if (!activeChatSelectionRange && !setSelectionRangeFromWindow()) return;

    if (type === 'bold') {
      wrapSelectedContent(() => document.createElement('strong'));
      hideBoldPopup();
      return;
    }
    if (type === 'italic') {
      wrapSelectedContent(() => document.createElement('em'));
      hideBoldPopup();
      return;
    }
    if (type === 'underline') {
      wrapSelectedContent(() => document.createElement('u'));
      hideBoldPopup();
      return;
    }
    if (type.startsWith('color:')) {
      const colorValue = type.split(':')[1];
      wrapSelectedContent(() => {
        const span = document.createElement('span');
        span.style.color = colorValue;
        return span;
      });
      hideBoldPopup();
      return;
    }
    if (type.startsWith('highlight:')) {
      const highlightValue = type.split(':')[1];
      wrapSelectedContent(() => {
        const span = document.createElement('span');
        span.style.background = highlightValue;
        span.style.borderRadius = '8px';
        span.style.padding = '1px 6px';
        return span;
      });
      hideBoldPopup();
    }
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
    const target = e.target instanceof Element ? e.target : null;
    if (!target) return;
    const bold = target.closest('strong.ai-bold');
    if (!bold) return;
    if (boldHideTimeout) {
      clearTimeout(boldHideTimeout);
      boldHideTimeout = null;
    }
    showBoldPopup(bold);
  });

  chatDiv.addEventListener('mouseout', (e) => {
    const target = e.target instanceof Element ? e.target : null;
    if (!target) return;
    const bold = target.closest('strong.ai-bold');
    if (!bold) return;
    const related = e.relatedTarget;
    if (related && related instanceof Node && boldPopup.contains(related)) return;
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

  boldGoogleBtn.addEventListener('click', () => {
    if (!activeBoldText) return;
    const query = encodeURIComponent(activeBoldText);
    window.open(`https://www.google.com/search?q=${query}`, '_blank');
    hideBoldPopup();
  });

  boldCopyBtn.addEventListener('click', () => {
    if (!activeBoldText) return;
    navigator.clipboard.writeText(activeBoldText);
    hideBoldPopup();
  });

  boldFollowupBtn.addEventListener('click', () => {
    if (!activeBoldText) return;
    input.value = `Follow-up: ${activeBoldText}`;
    backspaceBtn.classList.add('visible');
    input.focus();
    hideBoldPopup();
  });

  // Capture selection on mousedown (before browser can collapse it) then format on click
  const captureAndPrevent = (e) => {
    e.preventDefault();
    setSelectionRangeFromWindow();
  };

  colorBlueBtn.addEventListener('mousedown', captureAndPrevent);
  colorBlueBtn.addEventListener('click', () => formatSelection('color:#1d4ed8'));
  colorRedBtn.addEventListener('mousedown', captureAndPrevent);
  colorRedBtn.addEventListener('click', () => formatSelection('color:#b91c1c'));
  colorGreenBtn.addEventListener('mousedown', captureAndPrevent);
  colorGreenBtn.addEventListener('click', () => formatSelection('color:#166534'));
  highlightYellowBtn.addEventListener('mousedown', captureAndPrevent);
  highlightYellowBtn.addEventListener('click', () => formatSelection('highlight:#fef08a'));
  highlightMintBtn.addEventListener('mousedown', captureAndPrevent);
  highlightMintBtn.addEventListener('click', () => formatSelection('highlight:#bbf7d0'));
  highlightSkyBtn.addEventListener('mousedown', captureAndPrevent);
  highlightSkyBtn.addEventListener('click', () => formatSelection('highlight:#bfdbfe'));

  if (!inlineFormatShortcutBound) {
    document.addEventListener('keydown', (e) => {
      const hasModifier = e.metaKey || e.ctrlKey;
      if (!hasModifier || e.altKey) return;
      const currentChatDiv = document.getElementById('ai-assistant-chat');
      if (!currentChatDiv) return;
      const selection = window.getSelection();
      if (!selection || selection.rangeCount === 0) return;
      const range = selection.getRangeAt(0);
      if (range.collapsed || !currentChatDiv.contains(range.commonAncestorContainer)) return;

      const key = (e.key || '').toLowerCase();
      if (key === 'b') {
        e.preventDefault();
        formatSelection('bold');
      } else if (key === 'i') {
        e.preventDefault();
        formatSelection('italic');
      } else if (key === 'u') {
        e.preventDefault();
        formatSelection('underline');
      }
    }, true);
    inlineFormatShortcutBound = true;
  }

  // Handle text selection in chat
  function handleTextSelection() {
    const selection = window.getSelection();
    if (!selection) {
      hideBoldPopup();
      return;
    }

    const selectedText = selection.toString().trim();
    
    if (!selectedText) {
      hideBoldPopup();
      return;
    }

    if (selection.rangeCount === 0) {
      hideBoldPopup();
      return;
    }
    
    // Check if selection is within chat area
    const range = selection.getRangeAt(0);
    const isInChat = chatDiv.contains(range.commonAncestorContainer);
    
    if (isInChat) {
      activeBoldText = selectedText;
      setSelectionRangeFromWindow();
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
  
  // Image search button handler
  document.getElementById('ai-image-search-btn').addEventListener('click', () => handleImageSearch());

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
    
    if (btn.classList.contains('shorten-btn') || btn.classList.contains('lengthen-btn')) {
      const messageEl = btn.closest('.ai-message');
      const contentEl = messageEl ? messageEl.querySelector('.message-content') : null;
      let messageText = contentEl ? contentEl.innerText : '';
      messageText = messageText.replace(/^\s*\n+|\n+\s*$/g, '').trim();
      if (!messageText) return;

      const mode = btn.classList.contains('shorten-btn') ? 'shorten' : 'lengthen';
      const originalText = btn.textContent;
      btn.textContent = mode === 'shorten' ? 'Shortening...' : 'Lengthening...';
      btn.disabled = true;

      runBubbleRewrite(mode, messageText)
        .catch((err) => {
          console.error('Bubble rewrite failed:', err);
        })
        .finally(() => {
          btn.textContent = originalText;
          btn.disabled = false;
        });
    } else if (btn.classList.contains('copy-btn')) {
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
    } else if (btn.classList.contains('transpose-table-btn')) {
      const messageEl = btn.closest('.ai-message');
      const contentEl = messageEl.querySelector('.message-content');
      const table = contentEl.querySelector('table.ai-table');

      if (table) {
        transposeAiTable(table);
        const originalText = btn.textContent;
        btn.textContent = 'Transposed!';
        setTimeout(() => {
          btn.textContent = originalText;
        }, 1200);
      }
    } else if (btn.classList.contains('copy-image-btn')) {
      const messageEl = btn.closest('.ai-message');
      const originalText = btn.textContent;
      btn.textContent = 'Copying...';
      btn.disabled = true;

      copyBubbleAsImage(messageEl)
        .then(() => {
          btn.textContent = 'Image Copied!';
          setTimeout(() => {
            btn.textContent = originalText;
            btn.disabled = false;
          }, 1400);
        })
        .catch((err) => {
          console.error('Copy image failed:', err);
          btn.textContent = 'Copy Failed';
          setTimeout(() => {
            btn.textContent = originalText;
            btn.disabled = false;
          }, 1500);
        });
    } else if (btn.classList.contains('followup-btn')) {
      const inputEl = document.getElementById('ai-assistant-input');
      const sendBtn = document.getElementById('ai-assistant-send');
      // Capture the AI bubble text so sendMessage can tag the follow-up
      const msgEl = btn.closest('.ai-message');
      const contentEl = msgEl ? msgEl.querySelector('.message-content') : null;
      followUpContext = contentEl ? contentEl.innerText.trim() : '';
      // Style send button and input purple
      sendBtn.textContent = 'Follow-up';
      sendBtn.classList.add('followup-mode');
      inputEl.classList.add('followup-mode');
      inputEl.placeholder = 'Ask a follow-up question...';
      inputEl.focus();
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

function providerDisplayName(provider) {
  if (provider === 'chatgpt') return 'ChatGPT';
  if (provider === 'gemini') return 'Gemini';
  if (provider === 'pubmed') return 'PubMed';
  if (provider === 'jama') return 'JAMA';
  return 'ChatGPT';
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

function updateProviderButtons(provider) {
  const buttons = document.querySelectorAll('.engine-btn');
  buttons.forEach((btn) => {
    const p = btn.getAttribute('data-provider');
    btn.classList.toggle('active', p === provider);
  });
}

function updateResendButton() {
  const resendBtn = document.getElementById('ai-assistant-resend-engine');
  if (!resendBtn) return;

  if (resendPendingProvider && lastUserRequest) {
    resendBtn.textContent = `Send to ${providerDisplayName(resendPendingProvider)}`;
    resendBtn.classList.add('visible');
  } else {
    resendBtn.classList.remove('visible');
    resendBtn.textContent = '';
  }
}

async function loadResendState() {
  try {
    const data = await chrome.storage.local.get(['chatHistory', 'resendPendingProvider']);
    const history = data.chatHistory || [];
    resendPendingProvider = data.resendPendingProvider || '';

    // Track latest user request for "send to new engine" action.
    for (let i = history.length - 1; i >= 0; i--) {
      if (history[i].role === 'user') {
        lastUserRequest = history[i].content || '';
        break;
      }
    }
  } catch (_) {
    // Ignore storage read errors and keep defaults.
  }
  updateResendButton();
}

function setProvider(provider) {
  chrome.storage.sync.get('provider', async (result) => {
    const currentProvider = result.provider || 'chatgpt';
    if (provider === currentProvider) return;

    chrome.storage.sync.set({ provider }, async () => {
      updateProviderButtons(provider);
      resendPendingProvider = provider;
      await chrome.storage.local.set({ resendPendingProvider: provider });
      updateResendButton();
    });
  });
}

function closeMessenger() {
  if (messengerWindow) {
    messengerWindow.remove();
    messengerWindow = null;
  }
}

// ── Global text-selection popup ──────────────────────────────────────────────

// Route popup/keyboard actions to the top frame (works from iframes too)
function dispatchSelectionAction(action, text) {
  if (window === window.top) {
    if (action === 'summarize') summarizeSelectedText(text);
    else if (action === 'askAI') askAIAboutSelectedText(text);
    else if (action === 'save') saveSelectedText(text);
  } else {
    // Bubble up to the top frame's content script via postMessage
    window.top.postMessage({ type: 'AIFLY_ACTION', action, text }, '*');
  }
}

function initSelectionPopup() {
  if (document.getElementById('ai-selection-popup')) return;
  if (!document.body) return;

  const popup = document.createElement('div');
  popup.id = 'ai-selection-popup';
  popup.setAttribute('role', 'menu');
  popup.innerHTML = `
    <button class="sel-btn sel-google-btn" title="Google search selected text">Google</button>
    <div class="sel-divider"></div>
    <button class="sel-btn sel-summarize-btn" title="Summarize selected text (press 1)">Summarize <kbd>1</kbd></button>
    <div class="sel-divider"></div>
    <button class="sel-btn sel-ask-btn" title="Ask AI about selection (press 2)">Ask AI <kbd>2</kbd></button>
    <div class="sel-divider"></div>
    <button class="sel-btn sel-save-btn" title="Save snippet (press 4)">Save <kbd>4</kbd></button>
  `;
  document.body.appendChild(popup);

  popup.querySelector('.sel-google-btn').addEventListener('mousedown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    const text = currentSelectedText;
    hideSelectionPopup();
    window.open(`https://www.google.com/search?q=${encodeURIComponent(text)}`, '_blank');
  });

  popup.querySelector('.sel-summarize-btn').addEventListener('mousedown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    const text = currentSelectedText;
    hideSelectionPopup();
    dispatchSelectionAction('summarize', text);
  });

  popup.querySelector('.sel-ask-btn').addEventListener('mousedown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    const text = currentSelectedText;
    hideSelectionPopup();
    dispatchSelectionAction('askAI', text);
  });

  popup.querySelector('.sel-save-btn').addEventListener('mousedown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    dispatchSelectionAction('save', currentSelectedText);
  });

  // Hide when clicking outside
  document.addEventListener('mousedown', (e) => {
    const p = document.getElementById('ai-selection-popup');
    if (p && !p.contains(e.target)) {
      hideSelectionPopup();
    }
  });

  // Show on text selection (global — any page area except the messenger)
  document.addEventListener('mouseup', (e) => {
    setTimeout(() => handleGlobalTextSelection(e), 20);
  });
}

function handleGlobalTextSelection(e) {
  const popup = document.getElementById('ai-selection-popup');
  if (!popup) return;

  // Ignore clicks inside the popup itself
  if (popup.contains(e.target)) return;

  // Ignore selections inside the messenger window
  const messenger = document.getElementById('ai-assistant-messenger');
  if (messenger && messenger.contains(e.target)) return;

  const selection = window.getSelection();
  const selectedText = selection ? selection.toString().trim() : '';

  if (!selectedText || selectedText.length < 3) {
    hideSelectionPopup();
    return;
  }

  currentSelectedText = selectedText;

  // Position popup at the cursor location
  showSelectionPopup(e.clientX, e.clientY);
}

function showSelectionPopup(x, y) {
  const popup = document.getElementById('ai-selection-popup');
  if (!popup) return;

  popup.style.visibility = 'hidden';
  popup.classList.add('visible');
  selectionPopupVisible = true;

  // Measure after display
  const pw = popup.offsetWidth || 290;
  const ph = popup.offsetHeight || 46;

  // Place popup just below and to the right of the cursor
  let left = x + 8;
  let top  = y + 16;

  if (left + pw > window.innerWidth - 8) left = x - pw - 8;
  if (left < 8) left = 8;
  if (top + ph > window.innerHeight - 8) top = y - ph - 8;
  if (top < 8) top = 8;

  popup.style.left = `${left}px`;
  popup.style.top  = `${top}px`;
  popup.style.visibility = 'visible';
}

function hideSelectionPopup() {
  const popup = document.getElementById('ai-selection-popup');
  if (popup) popup.classList.remove('visible');
  selectionPopupVisible = false;
}

async function summarizeSelectedText(text) {
  if (!text) return;

  // Open messenger if not visible
  if (!messengerWindow || !messengerWindow.parentElement) {
    createMessenger();
    await new Promise(resolve => setTimeout(resolve, 200));
  }

  const input = document.getElementById('ai-assistant-input');
  if (!input) return;

  input.value = `Summarize the following text concisely. **Bold** every key term, concept, or important phrase in your response.\n\n"${text}"`;
  const backspaceBtn = document.getElementById('ai-assistant-backspace');
  if (backspaceBtn) backspaceBtn.classList.add('visible');

  // Auto-send silently (no user bubble)
  silentSend = true;
  document.getElementById('ai-assistant-send').click();
}

function askAIAboutSelectedText(text) {
  if (!text) return;

  // Open messenger if not visible
  if (!messengerWindow || !messengerWindow.parentElement) {
    createMessenger();
  }

  setTimeout(() => {
    const input = document.getElementById('ai-assistant-input');
    const backspaceBtn = document.getElementById('ai-assistant-backspace');
    if (input) {
      input.value = text;
      if (backspaceBtn) backspaceBtn.classList.add('visible');
      input.focus();
    }
  }, 200);
}

async function saveSelectedText(text) {
  if (!text) return;

  const data = await chrome.storage.local.get('savedSnippets');
  const snippets = data.savedSnippets || [];
  snippets.push({
    text,
    url:   window.location.href,
    title: document.title,
    timestamp: Date.now()
  });
  if (snippets.length > 200) snippets.shift();
  await chrome.storage.local.set({ savedSnippets: snippets });

  // Brief visual feedback on the save button
  const popup = document.getElementById('ai-selection-popup');
  if (popup) {
    const btn = popup.querySelector('.sel-save-btn');
    if (btn) {
      const orig = btn.innerHTML;
      btn.innerHTML = '✓ Saved!';
      btn.style.background = 'rgba(16, 185, 129, 0.55)';
      setTimeout(() => {
        btn.innerHTML = orig;
        btn.style.background = '';
        hideSelectionPopup();
      }, 1200);
    }
  }
}

async function sendMessage() {
  const input = document.getElementById('ai-assistant-input');
  const message = input.value.trim();

  if (!message) return;

  // Keep last user request for one-click "send to new engine" workflow.
  if (!silentSend) {
    lastUserRequest = message;
    chrome.storage.local.set({ lastUserRequest: message });
    updateResendButton();
  }

  // Tag message with follow-up context if active, then reset UI immediately
  const isFollowUp = !!followUpContext;
  let finalMessage = message;
  if (isFollowUp) {
    finalMessage = `Follow-up on this response:\n\n"${followUpContext}"\n\nUser question: ${message}`;
    followUpContext = '';
    const sendBtn = document.getElementById('ai-assistant-send');
    const inputEl = document.getElementById('ai-assistant-input');
    if (sendBtn) { sendBtn.textContent = 'Send'; sendBtn.classList.remove('followup-mode'); }
    if (inputEl) { inputEl.classList.remove('followup-mode'); inputEl.placeholder = 'Ask something...'; }
  }

  const chatDiv = document.getElementById('ai-assistant-chat');

  // Add user message (skip for silent sends e.g. summarize)
  const isSilent = silentSend;
  silentSend = false;

  if (!isSilent) {
    const userMsg = document.createElement('div');
    userMsg.className = 'ai-assistant-message user-message';
    userMsg.textContent = message;
    chatDiv.appendChild(userMsg);
    await saveChatMessage('user', message);
  }

  input.value = '';
  chatDiv.scrollTop = chatDiv.scrollHeight;

  // Show loading
  const loadingMsg = appendLoadingBubble(chatDiv);
  chatDiv.scrollTop = chatDiv.scrollHeight;

  try {
    // Get conversation history for context and medical mode
    const data = await chrome.storage.local.get('chatHistory');
    const history = data.chatHistory || [];
    
    // Get medical mode setting
    const syncData = await chrome.storage.sync.get('medicalMode');
    const medicalMode = syncData.medicalMode || false;
    const composedPrompt = `${finalMessage}\n\n${RESPONSE_FORMAT_GUIDANCE}`;
    
    // Prepend medical context if enabled
    let contextMessage = message;
    if (medicalMode) {
      contextMessage = 'Medical query (provide medication doses, frequencies, diagnosis criteria, and treatment protocols): ' + composedPrompt;
    } else {
      contextMessage = composedPrompt;
    }
    
    // Get AI response with conversation context
    const response = await requestAiResponse(contextMessage, history);

    // Remove loading message
    loadingMsg.remove();

    // Add AI response with formatting
    appendAiResponseBubble(chatDiv, response);

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

function transposeAiTable(table) {
  const rows = Array.from(table.querySelectorAll('tr')).map((row) => {
    return Array.from(row.querySelectorAll('td')).map((cell) => cell.innerHTML);
  });

  if (rows.length === 0) return;

  const maxCols = rows.reduce((max, row) => Math.max(max, row.length), 0);
  if (maxCols === 0) return;

  const transposed = [];
  for (let colIndex = 0; colIndex < maxCols; colIndex++) {
    const newRow = [];
    for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      newRow.push(rows[rowIndex][colIndex] ?? '');
    }
    transposed.push(newRow);
  }

  table.innerHTML = transposed
    .map((row) => `<tr>${row.map((cell) => `<td>${cell}</td>`).join('')}</tr>`)
    .join('');
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

function appendLoadingBubble(chatDiv) {
  const loadingMsg = document.createElement('div');
  loadingMsg.className = 'ai-assistant-message ai-message loading';
  loadingMsg.innerHTML = `
    <div class="thinking-bar">
      <div class="thinking-dots"><span></span><span></span><span></span></div>
      <div class="thinking-progress-track">
        <div class="thinking-progress-fill"></div>
      </div>
    </div>
  `;
  chatDiv.appendChild(loadingMsg);
  return loadingMsg;
}

function buildMessageActionsHtml(hasTable) {
  return `
    <button class="action-btn shorten-btn">Shorten</button>
    <button class="action-btn lengthen-btn">Lengthen</button>
    <button class="action-btn copy-btn">Copy</button>
    ${hasTable ? '<button class="action-btn copy-table-btn">Copy Table</button>' : ''}
    ${hasTable ? '<button class="action-btn transpose-table-btn">Transpose Table</button>' : ''}
    <button class="action-btn copy-image-btn">Copy as Image</button>
    <button class="action-btn followup-btn">Follow-up</button>
  `;
}

function appendAiResponseBubble(chatDiv, responseText) {
  const aiMsg = document.createElement('div');
  aiMsg.className = 'ai-assistant-message ai-message';

  const contentDiv = document.createElement('div');
  contentDiv.className = 'message-content';
  contentDiv.innerHTML = formatAIResponse(responseText);

  const actionsDiv = document.createElement('div');
  actionsDiv.className = 'message-actions';

  const hasTable = contentDiv.querySelector('table.ai-table');
  actionsDiv.innerHTML = buildMessageActionsHtml(!!hasTable);

  aiMsg.appendChild(contentDiv);
  aiMsg.appendChild(actionsDiv);
  chatDiv.appendChild(aiMsg);
  return aiMsg;
}

function requestAiResponse(message, history) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(
      { type: 'GET_AI_RESPONSE', message, history },
      (result) => {
        if (result && result.success) {
          resolve(result.response);
        } else {
          reject(new Error((result && result.error) || 'Failed to get AI response'));
        }
      }
    );
  });
}

async function runBubbleRewrite(mode, sourceText) {
  const chatDiv = document.getElementById('ai-assistant-chat');
  if (!chatDiv || !sourceText) return;

  const actionPrompt = mode === 'shorten'
    ? 'Rewrite the following response so it is significantly shorter while preserving key meaning and important facts.'
    : 'Rewrite the following response so it is more detailed and longer, with clearer explanation and additional useful context.';

  const composedPrompt = `${actionPrompt}\n\nOriginal response:\n"""\n${sourceText}\n"""\n\n${RESPONSE_FORMAT_GUIDANCE}`;
  const loadingMsg = appendLoadingBubble(chatDiv);
  chatDiv.scrollTop = chatDiv.scrollHeight;

  try {
    const data = await chrome.storage.local.get('chatHistory');
    const history = data.chatHistory || [];
    const response = await requestAiResponse(composedPrompt, history);
    loadingMsg.remove();
    appendAiResponseBubble(chatDiv, response);
    await saveChatMessage('assistant', response);
  } catch (error) {
    loadingMsg.remove();
    const errorMsg = document.createElement('div');
    errorMsg.className = 'ai-assistant-message ai-message';
    const content = document.createElement('div');
    content.className = 'message-content';
    content.textContent = `Error: ${error.message}`;
    errorMsg.appendChild(content);
    chatDiv.appendChild(errorMsg);
  }

  chatDiv.scrollTop = chatDiv.scrollHeight;
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
      
      actionsDiv.innerHTML = buildMessageActionsHtml(!!hasTable);
      
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
  if (!suggestionsDiv) return;

  // Remove old dynamic suggestions but keep the permanent Search Image button
  suggestionsDiv.querySelectorAll('.suggestion-btn:not(#ai-image-search-btn)').forEach(b => b.remove());

  const suggestions = ['Tell me more', 'Explain further', 'Give an example', 'What else?'];

  suggestions.forEach(text => {
    const btn = document.createElement('button');
    btn.className = 'suggestion-btn';
    btn.textContent = text;
    btn.addEventListener('click', () => {
      const input = document.getElementById('ai-assistant-input');
      if (!input) return;
      input.value = text;
      input.focus();
      document.getElementById('ai-assistant-send').click();
    });
    suggestionsDiv.appendChild(btn);
  });
}

async function copyBubbleAsImage(messageEl) {
  if (!messageEl) throw new Error('Message element not found.');

  const contentEl = messageEl.querySelector('.message-content');
  if (!contentEl) throw new Error('Message content not found.');

  const exportOuter = document.createElement('div');
  exportOuter.style.background = '#ffffff';
  exportOuter.style.padding = '18px';
  exportOuter.style.display = 'inline-block';
  exportOuter.style.borderRadius = '14px';

  const exportBubble = document.createElement('div');
  exportBubble.style.background = '#f1f3f5';
  exportBubble.style.color = '#212529';
  exportBubble.style.borderRadius = '10px 10px 10px 4px';
  exportBubble.style.padding = '14px 16px';
  exportBubble.style.fontFamily = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif";
  exportBubble.style.fontSize = '14px';
  exportBubble.style.lineHeight = '1.5';
  exportBubble.style.maxWidth = '560px';
  exportBubble.style.boxSizing = 'border-box';

  const clonedContent = contentEl.cloneNode(true);
  exportBubble.appendChild(clonedContent);
  exportOuter.appendChild(exportBubble);

  exportBubble.querySelectorAll('mark').forEach((markEl) => {
    markEl.style.background = 'linear-gradient(120deg, #ffeaa7 0%, #fdcb6e 100%)';
    markEl.style.color = '#2d3436';
    markEl.style.padding = '3px 8px';
    markEl.style.borderRadius = '8px';
    markEl.style.fontWeight = '500';
  });

  exportBubble.querySelectorAll('table').forEach((tableEl) => {
    tableEl.style.width = '100%';
    tableEl.style.borderCollapse = 'collapse';
    tableEl.style.background = '#ffffff';
    tableEl.style.marginTop = '8px';
    tableEl.style.marginBottom = '8px';
    tableEl.querySelectorAll('td').forEach((tdEl) => {
      tdEl.style.border = '1px solid #e9ecef';
      tdEl.style.padding = '8px 10px';
      tdEl.style.verticalAlign = 'top';
    });
  });

  const measuringStage = document.createElement('div');
  measuringStage.style.position = 'fixed';
  measuringStage.style.left = '-99999px';
  measuringStage.style.top = '0';
  measuringStage.style.pointerEvents = 'none';
  measuringStage.appendChild(exportOuter);
  document.body.appendChild(measuringStage);

  let width = 1;
  let height = 1;
  let serializedMarkup = '';
  try {
    const rect = exportOuter.getBoundingClientRect();
    width = Math.max(1, Math.ceil(rect.width));
    height = Math.max(1, Math.ceil(rect.height));
    serializedMarkup = new XMLSerializer().serializeToString(exportOuter);
  } finally {
    document.body.removeChild(measuringStage);
  }

  const svg = `
    <svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
      <foreignObject width="100%" height="100%">${serializedMarkup}</foreignObject>
    </svg>
  `;

  const blob = await svgToPngBlob(svg, width, height);
  if (!blob) throw new Error('Unable to render image blob.');

  if (!navigator.clipboard || typeof ClipboardItem === 'undefined') {
    throw new Error('Clipboard image API is not available in this browser context.');
  }

  await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
}

function svgToPngBlob(svgMarkup, width, height) {
  return new Promise((resolve, reject) => {
    const svgBlob = new Blob([svgMarkup], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(svgBlob);
    const img = new Image();
    img.onload = () => {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const ctx = canvas.getContext('2d');
        if (!ctx) {
          URL.revokeObjectURL(url);
          reject(new Error('2D canvas context unavailable.'));
          return;
        }
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, width, height);
        ctx.drawImage(img, 0, 0);
        canvas.toBlob((blob) => {
          URL.revokeObjectURL(url);
          resolve(blob);
        }, 'image/png');
      } catch (error) {
        URL.revokeObjectURL(url);
        reject(error);
      }
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Unable to rasterize SVG content.'));
    };
    img.src = url;
  });
}

async function copyImageFromUrlToClipboard(imageUrl) {
  if (!imageUrl) throw new Error('Image URL not found.');
  if (!navigator.clipboard || typeof ClipboardItem === 'undefined') {
    throw new Error('Clipboard image API is not available in this browser context.');
  }

  let blob = null;

  try {
    const directResp = await fetch(imageUrl);
    if (directResp.ok) {
      const directBlob = await directResp.blob();
      if (directBlob && directBlob.type.startsWith('image/')) {
        blob = directBlob;
      }
    }
  } catch (error) {
    console.warn('Direct image fetch failed, fallback will be used:', error);
  }

  if (!blob) {
    const dataUrl = await new Promise((resolve, reject) => {
      chrome.runtime.sendMessage({ type: 'FETCH_IMAGE_AS_DATA_URL', imageUrl }, (res) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        if (!res || !res.success || !res.dataUrl) {
          reject(new Error((res && res.error) || 'Unable to fetch image data.'));
          return;
        }
        resolve(res.dataUrl);
      });
    });
    blob = dataUrlToBlob(dataUrl);
  }

  if (!blob || !blob.type.startsWith('image/')) {
    throw new Error('Source is not an image.');
  }

  blob = await convertBlobToPng(blob);

  await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
}

function dataUrlToBlob(dataUrl) {
  const [header, body = ''] = String(dataUrl || '').split(',');
  if (!header || !body) throw new Error('Invalid image data received.');
  const mimeMatch = header.match(/data:([^;]+);base64/i);
  const mimeType = mimeMatch ? mimeMatch[1] : 'application/octet-stream';
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new Blob([bytes], { type: mimeType });
}

function convertBlobToPng(blob) {
  return new Promise((resolve, reject) => {
    const objectUrl = URL.createObjectURL(blob);
    const img = new Image();

    img.onload = () => {
      try {
        const width = Math.max(1, img.naturalWidth || img.width || 1);
        const height = Math.max(1, img.naturalHeight || img.height || 1);
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const ctx = canvas.getContext('2d');
        if (!ctx) {
          URL.revokeObjectURL(objectUrl);
          reject(new Error('2D canvas context unavailable.'));
          return;
        }

        ctx.drawImage(img, 0, 0, width, height);
        canvas.toBlob((pngBlob) => {
          URL.revokeObjectURL(objectUrl);
          if (!pngBlob) {
            reject(new Error('Unable to convert image to PNG.'));
            return;
          }
          resolve(pngBlob);
        }, 'image/png');
      } catch (error) {
        URL.revokeObjectURL(objectUrl);
        reject(error);
      }
    };

    img.onerror = () => {
      URL.revokeObjectURL(objectUrl);
      reject(new Error('Unable to decode image blob.'));
    };

    img.src = objectUrl;
  });
}

function setImageOverlayButtonFeedback(btn, text, delay = 1200) {
  if (!btn) return;
  const original = btn.textContent;
  btn.textContent = text;
  setTimeout(() => {
    btn.textContent = original;
  }, delay);
}

function ensureImagePreviewDialog() {
  let dialog = document.getElementById('ai-image-preview-dialog');
  if (dialog) return dialog;

  dialog = document.createElement('div');
  dialog.id = 'ai-image-preview-dialog';
  dialog.innerHTML = `
    <div class="ai-image-preview-shell">
      <button id="ai-image-preview-close" type="button" aria-label="Close image preview">×</button>
      <img id="ai-image-preview-img" alt="Image preview" />
      <div class="ai-image-preview-actions">
        <button id="ai-image-preview-copy" class="image-grid-overlay-btn" type="button">Copy</button>
        <button id="ai-image-preview-link" class="image-grid-overlay-btn" type="button">Link</button>
      </div>
    </div>
  `;

  const img = dialog.querySelector('#ai-image-preview-img');
  const shell = dialog.querySelector('.ai-image-preview-shell');
  let zoomScale = 1;
  const minZoom = 0.8;
  const maxZoom = 4;

  const applyZoom = () => {
    img.style.transform = `scale(${zoomScale})`;
  };

  const resetZoom = () => {
    zoomScale = 1;
    applyZoom();
  };

  const closeDialog = () => {
    dialog.classList.remove('visible');
    resetZoom();
  };

  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) {
      closeDialog();
    }
  });

  dialog.querySelector('#ai-image-preview-close').addEventListener('click', closeDialog);

  const previewCopyBtn = dialog.querySelector('#ai-image-preview-copy');
  const previewLinkBtn = dialog.querySelector('#ai-image-preview-link');

  previewCopyBtn.addEventListener('click', async (event) => {
    event.preventDefault();
    event.stopPropagation();
    const imageUrl = dialog.dataset.imageUrl || '';
    if (!imageUrl) return;
    try {
      await copyImageFromUrlToClipboard(imageUrl);
      setImageOverlayButtonFeedback(previewCopyBtn, 'Copied!');
    } catch (error) {
      console.error('Preview image copy failed:', error);
      setImageOverlayButtonFeedback(previewCopyBtn, 'Failed', 1500);
    }
  });

  previewLinkBtn.addEventListener('click', async (event) => {
    event.preventDefault();
    event.stopPropagation();
    const imageUrl = dialog.dataset.imageUrl || '';
    if (!imageUrl) return;
    try {
      await navigator.clipboard.writeText(imageUrl);
      setImageOverlayButtonFeedback(previewLinkBtn, 'Linked!');
    } catch (error) {
      console.error('Preview image link copy failed:', error);
      setImageOverlayButtonFeedback(previewLinkBtn, 'Failed', 1500);
    }
  });

  shell.addEventListener('wheel', (event) => {
    if (!dialog.classList.contains('visible')) return;
    event.preventDefault();

    const delta = event.deltaY < 0 ? 0.12 : -0.12;
    zoomScale = Math.max(minZoom, Math.min(maxZoom, zoomScale + delta));
    applyZoom();
  }, { passive: false });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && dialog.classList.contains('visible')) {
      closeDialog();
    }
  });

  document.body.appendChild(dialog);
  return dialog;
}

function openImagePreviewDialog(imageUrl, altText) {
  if (!imageUrl) return;
  const dialog = ensureImagePreviewDialog();
  const img = dialog.querySelector('#ai-image-preview-img');
  dialog.dataset.imageUrl = imageUrl;
  img.style.transform = 'scale(1)';
  img.src = imageUrl;
  img.alt = altText || 'Image preview';
  dialog.classList.add('visible');
}

async function handleImageSearch() {
  const input = document.getElementById('ai-assistant-input');
  const query = (input && input.value.trim()) || lastUserRequest;
  if (!query) return;

  if (!messengerWindow || !messengerWindow.parentElement) {
    createMessenger();
    await new Promise(r => setTimeout(r, 200));
  }

  const chatDiv = document.getElementById('ai-assistant-chat');
  if (!chatDiv) return;

  // Loading bubble
  const loadingMsg = document.createElement('div');
  loadingMsg.className = 'ai-assistant-message ai-message loading';
  loadingMsg.innerHTML = `
    <div class="thinking-bar">
      <div class="thinking-dots"><span></span><span></span><span></span></div>
      <div class="thinking-progress-track"><div class="thinking-progress-fill"></div></div>
    </div>`;
  chatDiv.appendChild(loadingMsg);
  chatDiv.scrollTop = chatDiv.scrollHeight;

  try {
    const urls = await new Promise((resolve, reject) => {
      chrome.runtime.sendMessage({ type: 'SEARCH_IMAGES', query }, (res) => {
        if (chrome.runtime.lastError) { reject(new Error(chrome.runtime.lastError.message)); return; }
        if (res && res.success) resolve(res.urls);
        else reject(new Error((res && res.error) || 'Image search failed.'));
      });
    });

    loadingMsg.remove();

    const bubble = document.createElement('div');
    bubble.className = 'ai-assistant-message ai-message image-grid-bubble';

    const header = document.createElement('div');
    header.className = 'message-content';
    header.textContent = `Images for "${query}"`;
    bubble.appendChild(header);

    if (!urls || urls.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'message-content';
      empty.textContent = 'No images found.';
      bubble.appendChild(empty);
    } else {
      const grid = document.createElement('div');
      grid.className = 'image-grid';
      urls.forEach(url => {
        const card = document.createElement('div');
        card.className = 'image-grid-card';

        const img = document.createElement('img');
        img.src = url;
        img.className = 'image-grid-item';
        img.alt = query;
        img.loading = 'lazy';

        const overlay = document.createElement('div');
        overlay.className = 'image-grid-overlay';

        const copyBtn = document.createElement('button');
        copyBtn.type = 'button';
        copyBtn.className = 'image-grid-overlay-btn';
        copyBtn.textContent = 'Copy';

        const linkBtn = document.createElement('button');
        linkBtn.type = 'button';
        linkBtn.className = 'image-grid-overlay-btn';
        linkBtn.textContent = 'Link';

        copyBtn.addEventListener('click', async (event) => {
          event.preventDefault();
          event.stopPropagation();
          try {
            await copyImageFromUrlToClipboard(url);
            setImageOverlayButtonFeedback(copyBtn, 'Copied!');
          } catch (error) {
            console.error('Image copy failed:', error);
            setImageOverlayButtonFeedback(copyBtn, 'Failed', 1500);
          }
        });

        linkBtn.addEventListener('click', async (event) => {
          event.preventDefault();
          event.stopPropagation();
          try {
            await navigator.clipboard.writeText(url);
            setImageOverlayButtonFeedback(linkBtn, 'Linked!');
          } catch (error) {
            console.error('Image link copy failed:', error);
            setImageOverlayButtonFeedback(linkBtn, 'Failed', 1500);
          }
        });

        img.addEventListener('click', () => {
          grid.querySelectorAll('.image-grid-card.active').forEach((activeCard) => {
            activeCard.classList.remove('active');
          });
          card.classList.add('active');
          openImagePreviewDialog(url, query);
        });

        overlay.appendChild(copyBtn);
        overlay.appendChild(linkBtn);
        card.appendChild(img);
        card.appendChild(overlay);
        grid.appendChild(card);
      });
      bubble.appendChild(grid);
    }

    chatDiv.appendChild(bubble);
    chatDiv.scrollTop = chatDiv.scrollHeight;
  } catch (err) {
    loadingMsg.className = 'ai-assistant-message ai-message';
    const c = document.createElement('div');
    c.className = 'message-content';
    c.textContent = `Image search error: ${err.message}`;
    loadingMsg.appendChild(c);
  }
}
