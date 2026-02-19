# 🚀 AiFly

Instant AI Assistant Overlay for Chrome

AiFly is a lightweight Chrome Extension that provides an instant AI chat overlay triggered by a global keyboard shortcut.

Press Alt + Space from any webpage to open a fully functional AI messenger powered by ChatGPT or Google Gemini — without leaving your current context.

## ✨ Why I Built This

Switching tabs to use AI breaks workflow and focus.

AiFly eliminates context switching by embedding a fast, keyboard-driven AI assistant directly into the browser using:

- Global hotkey detection
- Real-time DOM injection
- Persistent local storage
- Multi-provider AI support
- Smart response formatting

The goal: Zero friction AI access anywhere on the web.

## 🔥 Core Features

### ⚡ Global Hotkey Activation

- Default shortcut: Alt + Space
- Fully configurable via settings
- Works on all URLs (<all_urls>)
- Runs at document_start for immediate availability
- Handles blank tabs and dynamically creates missing DOM elements

Implementation highlights:

- Custom shortcut parser
- Modifier key detection (Alt, Ctrl, Shift, Meta)
- Escape key closes overlay
- Event captured at global level

### 🤖 Dual AI Provider Support

Users can toggle between:

- OpenAI ChatGPT
- Google Gemini

Provider selection is persisted using chrome.storage.sync.

Architecture:

- Content script handles UI
- Background service worker performs API calls
- Chrome message passing connects them

### 🧠 Smart Response Rendering Engine

AiFly does not just display plain text. It:

- Parses Markdown-style formatting
- Converts bullet points into styled elements
- Renders structured tables
- Supports highlighted text
- Automatically bolds detected medication names

Medication detection adds:

- Styled <strong> formatting
- Interactive hover popup
- Quick “Copy” and “Follow-up” actions

### 🪄 Interactive Text Selection Popup

Selecting bolded text opens a contextual floating menu:

- Copy selection
- Generate follow-up query

This is implemented with:

- Dynamic popup positioning
- Bounding rectangle calculations
- Visibility state control
- Hover timing management

### 💾 Persistent Chat History

- Stores up to 100 messages locally
- Uses Chrome storage API
- Restores history on reload
- No external database
- No server storage

### 🎚 Customization Options

Via options.html:

- Choose AI provider
- Enter API keys
- Customize hotkey
- Toggle medical mode
- Reset settings

API keys are stored locally using Chrome secure storage.

### 🛡 Privacy Architecture

AiFly does not collect any user data.

From the Privacy Policy:

- No server backend
- No analytics
- No API key collection
- No browsing tracking
- All data stored locally
- API calls go directly to OpenAI or Google

This was intentionally built as a client-only architecture.

## 🏗 Technical Architecture

- Manifest V3 Extension
- Background service worker
- Content script injection
- <all_urls> permission
- Chrome Storage API
- ActiveTab permission

Content Script Responsibilities:

- Global hotkey detection
- UI injection
- Messenger window creation
- Resizable modal implementation
- Smart formatting engine
- Text selection handling
- DOM state management

Options Page Logic:

- Provider toggle UI
- API key validation
- Shortcut customization
- Persistent sync storage

## 📁 Project Structure

AiFly/
│
├── manifest.json
├── background.js
├── content.js
├── options.html
├── options.js
├── icons/
│ ├── icon-16.png
│ ├── icon-48.png
│ └── icon-128.png
├── PRIVACY_POLICY.md
├── PUBLISH_CHECKLIST.md
├── package.sh
└── README.md

## ⌨ Keyboard Shortcuts

| Shortcut    | Action              |
| ----------- | ------------------- |
| Alt + Space | Toggle AI messenger |
| Escape      | Close messenger     |
| Enter       | Send message        |

Shortcut is configurable in Options.

## 🧩 Engineering Challenges Solved

- Hotkey detection across all pages
- Overlay injection into arbitrary DOM states
- Proper z-index isolation
- Escape handling
- State restoration after reload
- Provider abstraction layer
- Local persistence without backend
- Dynamic popup positioning
- Styling isolation without external CSS

## 🚀 Installation (Developer Mode)

1. Clone repository
2. Go to chrome://extensions
3. Enable Developer Mode
4. Click “Load Unpacked”
5. Select project folder
6. Add API key in Options

## 📌 Design Goals

- Zero tab switching
- Keyboard-first interaction
- Clean UI with minimal friction
- No backend dependency
- Full user privacy
- Fast injection performance
- Clean separation of UI and service logic

## 📈 Portfolio Notes

This project demonstrates:

- Chrome Extension (Manifest V3) development
- Content script architecture
- Background service worker communication
- DOM injection strategy
- Local persistence
- API abstraction
- Interactive UI state management
- Security-conscious client-side architecture
- UX-driven product thinking
