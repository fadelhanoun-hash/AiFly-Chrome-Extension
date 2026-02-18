# AiFly - AI Assistant Chrome Extension

A lightweight Chrome extension that provides quick AI assistance through a messenger window triggered by **Alt+Space**. Powered by OpenAI ChatGPT and Google Gemini.

## Features

✨ **Quick Access** - Press Alt+Space to open the messenger window anywhere on the web
💬 **Dual AI Providers** - Choose between OpenAI ChatGPT and Google Gemini
🧠 **Smart Responses** - Get concise, formatted answers with bold text and bullet points
💊 **Medication Detection** - Automatically bolds medication names with hover popups
📋 **Text Selection Popup** - Select any text in responses to copy or create follow-ups
💾 **Chat History** - Automatic conversation history storage (up to 100 messages)
🎚️ **Font Size Control** - Adjust text size for better readability
⌨️ **Easy Close** - Press Escape or click the close button to dismiss

## Installation

1. Clone or download this repository
2. Go to `chrome://extensions/`
3. Enable "Developer mode" (top right)
4. Click "Load unpacked" and select this folder
5. Set your OpenAI API key in the extension options

## Setup

### Adding Your API Keys

1. Click the extension icon in Chrome toolbar
2. Select "Options" or right-click → "Options"
3. Choose your preferred AI provider (ChatGPT or Gemini)
4. Enter your API key from the respective platform:
   - **ChatGPT**: Get your key from [OpenAI API Platform](https://platform.openai.com/api-keys)
   - **Gemini**: Get your key from [Google AI Studio](https://aistudio.google.com/app/apikey)
5. Click Save

### API Key Links

- [OpenAI ChatGPT API Keys](https://platform.openai.com/api-keys)
- [OpenAI Documentation](https://platform.openai.com/docs/guides/gpt)
- [Google Gemini API Keys](https://aistudio.google.com/app/apikey)
- [Google AI Documentation](https://ai.google.dev/docs)

## Usage

- **Open**: Press `Alt+Space` on any webpage
- **Send Message**: Type your question and press Enter or click Send
- **Close**: Press `Escape` or click the ✕ button
- **History**: All conversations are automatically saved

## File Structure

```
├── manifest.json      # Extension configuration
├── background.js      # Service worker for API calls
├── content.js         # Content script for hotkey listening
├── messenger.css      # Styling for the messenger window
└── README.md          # This file
```

## Keyboard Shortcuts

| Shortcut  | Action                  |
| --------- | ----------------------- |
| Alt+Space | Toggle messenger window |
| Escape    | Close messenger window  |
| Enter     | Send message            |

## Technical Details

- **APIs**: OpenAI GPT-3.5-turbo and Google Gemini Pro
- **Storage**: Chrome Storage API for chat history and settings
- **Communication**: Chrome Message Passing for background worker communication
- **Styling**: Clean white theme with responsive design
- **Features**:
  - Automatic medication name detection and formatting
  - Text selection detection with contextual popups
  - Font size persistence across sessions
  - Provider persistence across sessions

## Privacy

- Chat history is stored locally in your browser
- API requests are sent directly to OpenAI
- No data is shared with third parties

## License

MIT
