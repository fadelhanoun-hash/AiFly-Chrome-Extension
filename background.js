// Background service worker

// Browser-level keyboard shortcut (works even when focus is in another extension's sidebar)
if (chrome.commands && chrome.commands.onCommand) {
  chrome.commands.onCommand.addListener(async (command) => {
    if (command !== 'open-assistant') return;
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) return;
      // Send to the top frame (frameId 0) of the active tab
      await chrome.tabs.sendMessage(tab.id, { type: 'OPEN_MESSENGER' }, { frameId: 0 });
    } catch (e) {
      // Tab may not have a content script receiver (e.g. restricted pages) — silently ignore
      if (e && typeof e.message === 'string' && e.message.includes('Receiving end does not exist')) {
        return;
      }
      console.error('Open assistant command failed:', e);
    }
  });
}

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.type === 'GET_AI_RESPONSE') {
    getAIResponse(request.message, request.history).then(response => {
      sendResponse({ success: true, response });
    }).catch(error => {
      sendResponse({ success: false, error: error.message });
    });
    return true; // Will respond asynchronously
  }

  if (request.type === 'TEST_AI_CONNECTION') {
    testAIConnection(request.provider, request.apiKey).then((result) => {
      sendResponse(result);
    }).catch((error) => {
      sendResponse({ success: false, error: error.message });
    });
    return true;
  }

  if (request.type === 'SEARCH_IMAGES') {
    searchImages(request.query).then((urls) => {
      sendResponse({ success: true, urls });
    }).catch((error) => {
      sendResponse({ success: false, error: error.message });
    });
    return true;
  }
});

async function searchImages(query) {
  if (!query) throw new Error('No search query provided.');

  const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  // Step 1: fetch DuckDuckGo search page to obtain the vqd token
  const searchPageResp = await fetchWithTimeout(
    `https://duckduckgo.com/?q=${encodeURIComponent(query)}&ia=images`,
    { headers: { 'User-Agent': UA, 'Accept': 'text/html' } }
  );
  if (!searchPageResp.ok) throw new Error(`Image search unavailable (HTTP ${searchPageResp.status}).`);

  const html = await searchPageResp.text();
  const vqdMatch = html.match(/vqd=([\d-]+)/);
  if (!vqdMatch) throw new Error('Could not obtain image search token.');
  const vqd = vqdMatch[1];

  // Step 2: fetch image results JSON
  const imageApiUrl = `https://duckduckgo.com/i.js?q=${encodeURIComponent(query)}&vqd=${encodeURIComponent(vqd)}&f=,,,,,&p=1`;
  const imageResp = await fetchWithTimeout(imageApiUrl, {
    headers: {
      'User-Agent': UA,
      'Accept': 'application/json',
      'Referer': 'https://duckduckgo.com/'
    }
  });
  if (!imageResp.ok) throw new Error(`Image results unavailable (HTTP ${imageResp.status}).`);

  const data = await imageResp.json();
  const results = Array.isArray(data.results) ? data.results : [];
  const urls = results.slice(0, 15).map(r => r.thumbnail || r.image).filter(Boolean);
  return urls;
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 12000) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}

async function testAIConnection(provider, apiKey) {
  if (!apiKey) {
    return { success: false, error: 'API key is required.' };
  }

  if (provider === 'chatgpt') {
    const response = await fetchWithTimeout('https://api.openai.com/v1/models', {
      method: 'GET',
      headers: { 'Authorization': `Bearer ${apiKey}` }
    });

    if (response.ok) {
      return { success: true, message: 'OpenAI connection successful.' };
    }

    const errorData = await response.json().catch(() => ({}));
    return { success: false, error: errorData.error?.message || `OpenAI request failed (HTTP ${response.status}).` };
  }

  if (provider === 'gemini') {
    const response = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`, {
      method: 'GET'
    });

    if (response.ok) {
      return { success: true, message: 'Gemini connection successful.' };
    }

    const errorData = await response.json().catch(() => ({}));
    return { success: false, error: errorData.error?.message || `Gemini request failed (HTTP ${response.status}).` };
  }

  if (provider === 'openevidence') {
    const response = await fetchWithTimeout('https://api.openevidence.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model: 'openevidence-1',
        messages: [{ role: 'user', content: 'Connection test' }],
        max_tokens: 16,
        temperature: 0
      })
    });

    if (response.ok) {
      return { success: true, message: 'Open Evidence connection successful.' };
    }

    const errorData = await response.json().catch(() => ({}));
    return { success: false, error: errorData.error?.message || `Open Evidence request failed (HTTP ${response.status}).` };
  }

  return { success: false, error: 'Unsupported provider.' };
}

async function getAIResponse(message, history = []) {
  const data = await chrome.storage.sync.get(['provider', 'chatgpt_key', 'gemini_key', 'openevidence_key', 'jama_key']);
  const provider = data.provider || 'chatgpt';

  if (provider === 'chatgpt') {
    return await getChatGPTResponse(message, data.chatgpt_key, history);
  } else if (provider === 'gemini') {
    return await getGeminiResponse(message, data.gemini_key, history);
  } else if (provider === 'openevidence') {
    return await getOpenEvidenceResponse(message, data.openevidence_key, history);
  } else if (provider === 'jama') {
    return await getJamaResponse(message, data.jama_key, history);
  }
}

async function getJamaResponse(message, apiKey, history = []) {
  if (!apiKey) {
    return '⚠️ JAMA does not provide a public chat API key by default. Add a configured JAMA endpoint/key or switch engine.';
  }

  // Placeholder behavior: JAMA does not expose a public chat-completions API.
  return '⚠️ JAMA engine is selected, but no public JAMA conversational API endpoint is available in this build. Switch to ChatGPT, Gemini, or OpenEvidence.';
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

async function getOpenEvidenceResponse(message, apiKey, history = []) {
  if (!apiKey) {
    return "⚠️ Please set your Open Evidence API key in the extension settings.";
  }

  try {
    // Build conversation history - get last 10 messages for context
    const recentHistory = history.slice(-10);
    const messages = [
      {
        role: 'system',
        content: 'You are an evidence-based medical AI assistant. Provide accurate, clinically relevant information with citations when possible. Format responses with **bold** for key medical terms, ==highlight== for critical information (doses, warnings), use bullet points for clarity, and tables for comparisons. Be concise but thorough for medical queries.'
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

    // Open Evidence API endpoint - this follows a ChatGPT-like structure
    // Note: Adjust the endpoint URL based on Open Evidence's actual API documentation
    const response = await fetch('https://api.openevidence.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model: 'openevidence-1',
        messages: messages,
        temperature: 0.3, // Lower temperature for medical accuracy
        max_tokens: 800
      })
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      const errorMsg = errorData.error?.message || `HTTP ${response.status}`;
      throw new Error(`Open Evidence API Error: ${errorMsg}`);
    }

    const result = await response.json();
    return result.choices[0].message.content;
  } catch (error) {
    console.error('Open Evidence Error:', error);
    return `❌ ${error.message}`;
  }
}

