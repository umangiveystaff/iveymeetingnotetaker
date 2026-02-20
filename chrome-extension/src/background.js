/**
 * background.js — Service Worker (MV3)
 * 
 * Coordinates the full pipeline:
 *   tabCapture → offscreen audio/whisper → transcript store → Ollama summarization
 * 
 * Privacy: No audio or text leaves this device. Only localhost:11434 is contacted.
 */

// ── Constants ──────────────────────────────────────────────────────────────────
const OFFSCREEN_URL = chrome.runtime.getURL('offscreen.html');
const OLLAMA_URL = 'http://127.0.0.1:11434/v1/chat/completions';
const OLLAMA_MODEL = 'llama3.2';
const KEEP_ALIVE_ALARM = 'keepAlive';

// ── State (persisted in session storage to survive SW restart) ─────────────────
let currentSpeaker = 'Unknown';
let isRecording = false;

// Persist recording state so popup can query it after SW restart
async function saveState(patch) {
    await chrome.storage.session.set(patch);
}
async function loadState() {
    const s = await chrome.storage.session.get(['isRecording', 'transcript', 'startTime']);
    isRecording = s.isRecording ?? false;
    return s;
}

// ── Keep service worker alive ──────────────────────────────────────────────────
chrome.alarms.create(KEEP_ALIVE_ALARM, { periodInMinutes: 0.4 });
chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === KEEP_ALIVE_ALARM) { /* heartbeat — keeps SW alive */ }
});

// ── Message router ─────────────────────────────────────────────────────────────
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    switch (msg.action) {

        case 'speakerUpdate':
            // From content.js: who is currently speaking
            currentSpeaker = msg.speakerName || 'Unknown';
            return false;

        case 'transcriptChunk':
            // From offscreen.js: a new transcribed text chunk
            handleTranscriptChunk(msg.text, msg.timestamp).then(() => sendResponse({ ok: true }));
            return true; // async

        case 'startRecording':
            startRecording(msg.tabId).then(sendResponse);
            return true;

        case 'stopRecording':
            stopRecording().then(sendResponse);
            return true;

        case 'generateNotes':
            generateNotes().then(sendResponse);
            return true;

        case 'getState':
            loadState().then(sendResponse);
            return true;
    }
});

// ── Start recording ────────────────────────────────────────────────────────────
async function startRecording(tabId) {
    try {
        isRecording = true;

        // Get stream ID (must happen in background, before offscreen exists)
        const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tabId });

        // Create or reuse offscreen document
        const existingContexts = await chrome.runtime.getContexts({
            contextTypes: ['OFFSCREEN_DOCUMENT'],
            documentUrls: [OFFSCREEN_URL],
        });
        if (!existingContexts.length) {
            await chrome.offscreen.createDocument({
                url: OFFSCREEN_URL,
                reasons: ['USER_MEDIA'],
                justification: 'Capture Teams audio for local transcription with Whisper',
            });
        }

        // Reset transcript
        await saveState({
            isRecording: true,
            transcript: [],
            startTime: Date.now(),
        });

        // Tell offscreen to start capturing
        await chrome.runtime.sendMessage({
            action: 'startCapture',
            streamId,
            targetTabId: tabId,
        });

        return { ok: true };
    } catch (err) {
        console.error('[background] startRecording error:', err);
        isRecording = false;
        await saveState({ isRecording: false });
        return { ok: false, error: err.message };
    }
}

// ── Stop recording ─────────────────────────────────────────────────────────────
async function stopRecording() {
    isRecording = false;
    await saveState({ isRecording: false });

    try {
        // Tell offscreen to stop
        await chrome.runtime.sendMessage({ action: 'stopCapture' });
        // Close offscreen document
        await chrome.offscreen.closeDocument();
    } catch (_) { /* ignore if already closed */ }

    return { ok: true };
}

// ── Handle incoming transcript chunk ──────────────────────────────────────────
async function handleTranscriptChunk(text, timestamp) {
    if (!text?.trim()) return;

    const { transcript = [] } = await chrome.storage.session.get('transcript');

    const entry = {
        speaker: currentSpeaker,
        text: text.trim(),
        timestamp: timestamp || Date.now(),
        id: transcript.length,
    };

    transcript.push(entry);
    await chrome.storage.session.set({ transcript });

    // Notify popup if open
    try {
        await chrome.runtime.sendMessage({ action: 'transcriptUpdate', entry });
    } catch (_) { /* popup may not be open */ }
}

// ── Generate meeting notes via Ollama ─────────────────────────────────────────
async function generateNotes() {
    const { transcript = [] } = await chrome.storage.session.get('transcript');

    if (!transcript.length) {
        return { ok: false, error: 'No transcript to summarize.' };
    }

    // Build the formatted transcript string
    const formattedTranscript = transcript.map(e => {
        const t = new Date(e.timestamp).toLocaleTimeString();
        return `[${t}] ${e.speaker}: ${e.text}`;
    }).join('\n');

    const systemPrompt = `You are an expert meeting summarizer. Generate structured meeting notes from the transcript below.
The transcript includes real speaker names captured from Microsoft Teams.

Output a complete Markdown document with these exact sections:

# [Meeting Title — infer from content]

**Date:** ${new Date().toLocaleDateString()}  
**Attendees:** [list unique speakers]

## Summary
[2-3 sentence executive summary]

## Key Decisions
- **[Decision]** — Owner: [Speaker who proposed/confirmed it]

## Action Items
| Owner | Task | Due | Quote |
| --- | --- | --- | --- |
[one row per commitment found in transcript]

## Blockers & Risks
- [Blocker/Risk] — raised by [Speaker]

## Discussion Highlights
[paragraph summary of main topics, referencing speakers]

## Next Steps
- [Next step] — Owner: [Name], By: [date or TBD]

RULES:
- Only use information from the transcript. Do not invent.
- Attribute every action item to the speaker who committed to it.
- If a section has nothing to report, write "None noted."`;

    const userPrompt = `TRANSCRIPT:\n\n${formattedTranscript}`;

    try {
        const res = await fetch(OLLAMA_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: OLLAMA_MODEL,
                messages: [
                    { role: 'system', content: systemPrompt },
                    { role: 'user', content: userPrompt },
                ],
                stream: false,
            }),
        });

        if (!res.ok) {
            const errText = await res.text();
            return { ok: false, error: `Ollama error ${res.status}: ${errText}` };
        }

        const data = await res.json();
        const notes = data.choices?.[0]?.message?.content?.trim();

        if (!notes) return { ok: false, error: 'Ollama returned empty response.' };

        await chrome.storage.session.set({ notes });
        return { ok: true, notes };

    } catch (err) {
        return { ok: false, error: `Could not reach Ollama at ${OLLAMA_URL}. Make sure it is running: ollama serve` };
    }
}
