// Background service worker

// Browser-level keyboard shortcut (works even when focus is in another extension's sidebar)
if (chrome.commands && chrome.commands.onCommand) {
  chrome.commands.onCommand.addListener(async (command) => {
    if (command !== 'open-assistant') return;
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab || !tab.id) return;
      const { disabledRules = [] } = await chrome.storage.sync.get('disabledRules');
      if (isDisabledForUrl(tab.url, disabledRules)) return;
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

  if (request.type === 'FETCH_IMAGE_AS_DATA_URL') {
    fetchImageAsDataUrl(request.imageUrl).then((dataUrl) => {
      sendResponse({ success: true, dataUrl });
    }).catch((error) => {
      sendResponse({ success: false, error: error.message });
    });
    return true;
  }
});

async function fetchImageAsDataUrl(imageUrl) {
  if (!imageUrl) throw new Error('Image URL is required.');

  const response = await fetchWithTimeout(imageUrl, {
    method: 'GET',
    headers: {
      'Accept': 'image/*,*/*;q=0.8'
    }
  }, 15000);

  if (!response.ok) {
    throw new Error(`Image fetch failed (HTTP ${response.status}).`);
  }

  const blob = await response.blob();
  if (!blob || !blob.type || !blob.type.startsWith('image/')) {
    throw new Error('Fetched resource is not an image.');
  }

  const dataUrl = await blobToDataUrl(blob);
  return dataUrl;
}

function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      if (typeof reader.result === 'string') {
        resolve(reader.result);
      } else {
        reject(new Error('Failed to encode image data.'));
      }
    };
    reader.onerror = () => reject(new Error('Failed to read image blob.'));
    reader.readAsDataURL(blob);
  });
}

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

const DEFAULT_PUBMED_API_KEY = '2fecec3e1f74d131a676e449a8a89f27fb09';
const PUBMED_BASE_URL = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils';

function getPubMedApiKey(apiKey) {
  const key = (apiKey || '').trim();
  return key || DEFAULT_PUBMED_API_KEY;
}

function buildPubMedQuery(message) {
  return String(message || '')
    .replace(/\s+/g, ' ')
    .trim();
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

  if (provider === 'pubmed') {
    const key = getPubMedApiKey(apiKey);
    const response = await fetchWithTimeout(
      `${PUBMED_BASE_URL}/einfo.fcgi?db=pubmed&retmode=json&api_key=${encodeURIComponent(key)}`,
      { method: 'GET' }
    );

    if (response.ok) {
      return { success: true, message: 'PubMed connection successful.' };
    }

    const errorText = await response.text().catch(() => '');
    return { success: false, error: errorText || `PubMed request failed (HTTP ${response.status}).` };
  }

  return { success: false, error: 'Unsupported provider.' };
}

async function getAIResponse(message, history = []) {
  const data = await chrome.storage.sync.get(['provider', 'chatgpt_key', 'gemini_key', 'pubmed_key', 'openevidence_key', 'jama_key']);
  const provider = data.provider === 'openevidence' ? 'pubmed' : (data.provider || 'chatgpt');

  if (provider === 'chatgpt') {
    return await getChatGPTResponse(message, data.chatgpt_key, history);
  } else if (provider === 'gemini') {
    return await getGeminiResponse(message, data.gemini_key, history);
  } else if (provider === 'pubmed') {
    return await getPubMedResponse(message, data.pubmed_key || data.openevidence_key, history);
  } else if (provider === 'jama') {
    return await getJamaResponse(message, data.jama_key, history);
  }
}

async function getJamaResponse(message, apiKey, history = []) {
  if (!apiKey) {
    return '⚠️ JAMA does not provide a public chat API key by default. Add a configured JAMA endpoint/key or switch engine.';
  }

  // Placeholder behavior: JAMA does not expose a public chat-completions API.
  return '⚠️ JAMA engine is selected, but no public JAMA conversational API endpoint is available in this build. Switch to ChatGPT, Gemini, or PubMed.';
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

async function getPubMedResponse(message, apiKey, history = []) {
  const _ = history; // Reserved for future query refinement from conversation context.
  const query = buildPubMedQuery(message);
  if (!query) {
    return '⚠️ Please enter a medical query to search PubMed.';
  }

  const key = getPubMedApiKey(apiKey);

  try {
    const searchUrl = `${PUBMED_BASE_URL}/esearch.fcgi?db=pubmed&retmode=json&retmax=6&sort=relevance&term=${encodeURIComponent(query)}&api_key=${encodeURIComponent(key)}`;
    const searchResp = await fetchWithTimeout(searchUrl, { method: 'GET' });
    if (!searchResp.ok) {
      throw new Error(`PubMed ESearch failed (HTTP ${searchResp.status})`);
    }

    const searchData = await searchResp.json();
    const ids = searchData?.esearchresult?.idlist || [];
    if (!Array.isArray(ids) || ids.length === 0) {
      return `No PubMed articles found for: **${query}**`;
    }

    const summaryUrl = `${PUBMED_BASE_URL}/esummary.fcgi?db=pubmed&retmode=json&id=${encodeURIComponent(ids.join(','))}&api_key=${encodeURIComponent(key)}`;
    const summaryResp = await fetchWithTimeout(summaryUrl, { method: 'GET' });
    if (!summaryResp.ok) {
      throw new Error(`PubMed ESummary failed (HTTP ${summaryResp.status})`);
    }

    const summaryData = await summaryResp.json();
    const uids = summaryData?.result?.uids || [];
    const lines = [];

    uids.slice(0, 5).forEach((uid, index) => {
      const item = summaryData.result[uid] || {};
      const title = String(item.title || 'Untitled').replace(/\s+/g, ' ').trim();
      const journal = String(item.fulljournalname || item.source || 'Unknown journal').trim();
      const pubdate = String(item.pubdate || '').trim();
      const link = `https://pubmed.ncbi.nlm.nih.gov/${uid}/`;

      lines.push(
        `${index + 1}. **${title}**\n- Journal: ${journal}${pubdate ? ` (${pubdate})` : ''}\n- PMID: ${uid}\n- Link: ${link}`
      );
    });

    return [
      `Top PubMed results for **${query}**:`,
      '',
      lines.join('\n\n'),
      '',
      'Tip: refine your query with terms like trial type, population, or year range (example: `diabetes metformin randomized controlled trial 2022:2026[dp]`).'
    ].join('\n');
  } catch (error) {
    console.error('PubMed Error:', error);
    return `❌ ${error.message}`;
  }
}
