// Background service worker
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.type === 'GET_AI_RESPONSE') {
    getAIResponse(request.message, request.history).then(response => {
      sendResponse({ success: true, response });
    }).catch(error => {
      sendResponse({ success: false, error: error.message });
    });
    return true; // Will respond asynchronously
  }
});

async function getAIResponse(message, history = []) {
  const data = await chrome.storage.sync.get(['provider', 'chatgpt_key', 'gemini_key']);
  const provider = data.provider || 'chatgpt';

  if (provider === 'chatgpt') {
    return await getChatGPTResponse(message, data.chatgpt_key, history);
  } else if (provider === 'gemini') {
    return await getGeminiResponse(message, data.gemini_key, history);
  }
}

async function getChatGPTResponse(message, apiKey, history = []) {
  if (!apiKey) {
    return "⚠️ Please set your OpenAI API key in the extension settings.";
  }

  try {
    // Build conversation history - get last 10 messages for context
    const recentHistory = history.slice(-10);
    const messages = [
      {
        role: 'system',
        content: 'You are a concise AI assistant. Keep responses SHORT (2-4 sentences max unless asked for details). Always format for readability: use **bold** for key terms, ==highlight== important facts/numbers, use bullet points (- or •), arrows (→) for steps, and tables when needed. Be direct and to the point. Detect follow-up questions from context.'
      }
    ];

    // Add conversation history
    recentHistory.forEach(msg => {
      messages.push({
        role: msg.role === 'user' ? 'user' : 'assistant',
        content: msg.content
      });
    });

    // Add current message
    messages.push({
      role: 'user',
      content: message
    });

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model: 'gpt-3.5-turbo',
        messages: messages,
        temperature: 0.7,
        max_tokens: 500
      })
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      const errorMsg = errorData.error?.message || `HTTP ${response.status}`;
      throw new Error(`OpenAI API Error: ${errorMsg}`);
    }

    const result = await response.json();
    return result.choices[0].message.content;
  } catch (error) {
    console.error('ChatGPT Error:', error);
    return `❌ ${error.message}`;
  }
}

async function getGeminiResponse(message, apiKey, history = []) {
  if (!apiKey) {
    return "⚠️ Please set your Google Gemini API key in the extension settings.";
  }

  try {
    // Build conversation history - get last 10 messages
    const recentHistory = history.slice(-10);
    
    // Format history for Gemini
    const contents = [];
    recentHistory.forEach(msg => {
      contents.push({
        role: msg.role === 'user' ? 'user' : 'model',
        parts: [{ text: msg.content }]
      });
    });

    // Add system prompt and current message
    const systemPrompt = 'Be CONCISE (2-4 sentences unless details needed). Format: use **bold** for key terms, ==highlight== important facts/numbers, bullet points (- or •), arrows (→) for steps, tables when needed. Be direct. Detect follow-ups from context.';
    
    contents.push({
      role: 'user',
      parts: [{ text: `${systemPrompt}\n\nUser question: ${message}` }]
    });

    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${apiKey}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: contents
      })
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      const errorMsg = errorData.error?.message || `HTTP ${response.status}`;
      throw new Error(`Gemini API Error: ${errorMsg}`);
    }

    const result = await response.json();
    return result.candidates[0].content.parts[0].text;
  } catch (error) {
    console.error('Gemini Error:', error);
    return `❌ ${error.message}`;
  }
}
