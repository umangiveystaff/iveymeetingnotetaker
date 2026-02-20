/**
 * popup.js — Extension popup UI controller
 *
 * State machine:  idle → recording → stopping → generating → notes-ready
 * All communication via chrome.runtime.sendMessage to background.js
 */

// ── DOM refs ───────────────────────────────────────────────────────────────────
const statusBadge = document.getElementById('statusBadge');
const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');
const teamsBanner = document.getElementById('teamsBanner');
const btnRecord = document.getElementById('btnRecord');
const btnIcon = document.getElementById('btnIcon');
const btnLabel = document.getElementById('btnLabel');
const timer = document.getElementById('timer');
const timerDisplay = document.getElementById('timerDisplay');
const currentSpeakerTag = document.getElementById('currentSpeakerTag');
const transcriptPanel = document.getElementById('transcriptPanel');
const transcriptFeed = document.getElementById('transcriptFeed');
const entryCount = document.getElementById('entryCount');
const generateRow = document.getElementById('generateRow');
const btnGenerate = document.getElementById('btnGenerate');
const generateLabel = document.getElementById('generateLabel');
const notesPanel = document.getElementById('notesPanel');
const notesContent = document.getElementById('notesContent');
const btnDownloadMd = document.getElementById('btnDownloadMd');
const btnDownloadTxt = document.getElementById('btnDownloadTxt');
const btnCopy = document.getElementById('btnCopy');

// ── App state ──────────────────────────────────────────────────────────────────
let appState = 'idle';   // idle | recording | stopping | generating | done
let timerInterval = null;
let startTime = null;
let transcript = [];
let notes = '';
let teamsTabId = null;

// Speaker → colour mapping (auto-assigned)
const speakerColours = ['#6366f1', '#ec4899', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6', '#ef4444', '#14b8a6'];
const speakerMap = new Map();
function getSpeakerColour(name) {
    if (!speakerMap.has(name)) speakerMap.set(name, speakerColours[speakerMap.size % speakerColours.length]);
    return speakerMap.get(name);
}

// ── Initialise ─────────────────────────────────────────────────────────────────
async function init() {
    // Restore state from previous session
    const state = await bg('getState');
    if (state.isRecording) {
        appState = 'recording';
        startTime = state.startTime || Date.now();
        transcript = state.transcript || [];
        renderTranscript(transcript);
        startTimer();
        setRecordingUI();
    }

    // Check if Teams tab is open
    const tabs = await chrome.tabs.query({
        url: ['https://teams.microsoft.com/*', 'https://teams.live.com/*'],
        currentWindow: false,
    });
    if (tabs.length === 0) {
        teamsBanner.style.display = 'flex';
        btnRecord.disabled = true;
        btnRecord.classList.add('btn-disabled');
    } else {
        teamsTabId = tabs.find(t => t.active)?.id || tabs[tabs.length - 1].id;
    }
}

// ── Record button ──────────────────────────────────────────────────────────────
btnRecord.addEventListener('click', async () => {
    if (appState === 'idle') {
        await startRecording();
    } else if (appState === 'recording') {
        await stopRecording();
    }
});

async function startRecording() {
    setStatus('Starting…', 'loading');
    btnRecord.disabled = true;

    // Get the active Teams tab
    const [activeTeamsTab] = await chrome.tabs.query({
        url: ['https://teams.microsoft.com/*', 'https://teams.live.com/*'],
        active: true, currentWindow: true,
    }).catch(() => []);

    // Fallback: use any Teams tab
    const allTeamsTabs = await chrome.tabs.query({
        url: ['https://teams.microsoft.com/*', 'https://teams.live.com/*'],
    });

    const tab = activeTeamsTab || allTeamsTabs[allTeamsTabs.length - 1];
    if (!tab) {
        setStatus('No Teams tab found', 'error');
        btnRecord.disabled = false;
        return;
    }

    teamsTabId = tab.id;

    const result = await bg('startRecording', { tabId: tab.id });
    if (!result.ok) {
        setStatus('Error: ' + result.error, 'error');
        btnRecord.disabled = false;
        return;
    }

    appState = 'recording';
    startTime = Date.now();
    transcript = [];

    startTimer();
    setRecordingUI();
    transcriptPanel.style.display = 'block';
    btnRecord.disabled = false;
}

async function stopRecording() {
    appState = 'stopping';
    setStatus('Stopping…', 'loading');
    btnRecord.disabled = true;
    btnIcon.textContent = '⏹';
    btnLabel.textContent = 'Stopping…';

    stopTimer();
    await bg('stopRecording');

    appState = 'done';
    setStatus('Recording saved', 'idle');
    setIdleUI();
    btnRecord.disabled = false;

    if (transcript.length > 0) {
        generateRow.style.display = 'flex';
    }
}

// ── Generate notes ─────────────────────────────────────────────────────────────
btnGenerate.addEventListener('click', async () => {
    if (appState === 'generating') return;
    appState = 'generating';
    generateLabel.textContent = 'Generating…';
    btnGenerate.disabled = true;
    setStatus('Summarising with Ollama…', 'loading');

    const result = await bg('generateNotes');

    if (!result.ok) {
        setStatus('Ollama error — is it running?', 'error');
        generateLabel.textContent = 'Generate Meeting Notes';
        btnGenerate.disabled = false;
        appState = 'done';

        if (result.error?.includes('localhost')) {
            notesPanel.style.display = 'block';
            notesContent.innerHTML = `<pre class="error-msg">Could not reach Ollama.\n\nRun this in a terminal:\n  ollama serve\n  ollama pull llama3.2\n\nThen try again.</pre>`;
        }
        return;
    }

    notes = result.notes;
    appState = 'notes-ready';
    setStatus('Notes ready', 'idle');
    generateLabel.textContent = '✓ Notes generated';
    btnGenerate.disabled = false;

    notesPanel.style.display = 'block';
    renderMarkdown(notes, notesContent);
});

// ── Download / copy buttons ────────────────────────────────────────────────────
btnDownloadMd.addEventListener('click', () => download(notes, 'meeting-notes.md', 'text/markdown'));
btnDownloadTxt.addEventListener('click', () => {
    const txt = transcript.map(e => `[${new Date(e.timestamp).toLocaleTimeString()}] ${e.speaker}: ${e.text}`).join('\n');
    download(txt, 'transcript.txt', 'text/plain');
});
btnCopy.addEventListener('click', async () => {
    await navigator.clipboard.writeText(notes).catch(() => { });
    btnCopy.textContent = '✓';
    setTimeout(() => { btnCopy.textContent = '📋'; }, 1500);
});

function download(content, filename, type) {
    const blob = new Blob([content], { type });
    const a = Object.assign(document.createElement('a'), {
        href: URL.createObjectURL(blob),
        download: filename,
    });
    a.click();
}

// ── Live transcript listener ───────────────────────────────────────────────────
chrome.runtime.onMessage.addListener((msg) => {
    if (msg.action === 'transcriptUpdate' && msg.entry) {
        transcript.push(msg.entry);
        appendTranscriptEntry(msg.entry);
        entryCount.textContent = `${transcript.length} entries`;
        currentSpeakerTag.textContent = msg.entry.speaker;
        currentSpeakerTag.style.display = 'inline-flex';
        currentSpeakerTag.style.background = getSpeakerColour(msg.entry.speaker);
    }
    if (msg.action === 'modelLoadProgress') {
        setStatus(`Loading Whisper… ${msg.progress}%`, 'loading');
    }
    if (msg.action === 'captureError') {
        setStatus('Capture error: ' + msg.error, 'error');
    }
});

// ── Transcript rendering ───────────────────────────────────────────────────────
function renderTranscript(entries) {
    transcriptFeed.innerHTML = '';
    entries.forEach(appendTranscriptEntry);
    entryCount.textContent = `${entries.length} entries`;
}

function appendTranscriptEntry(entry) {
    const t = new Date(entry.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const el = document.createElement('div');
    el.className = 'transcript-entry';
    const colour = getSpeakerColour(entry.speaker);
    el.innerHTML = `
    <div class="entry-header">
      <span class="speaker-badge" style="background:${colour}22;color:${colour};border-color:${colour}44">${entry.speaker}</span>
      <span class="entry-time">${t}</span>
    </div>
    <div class="entry-text">${escHtml(entry.text)}</div>
  `;
    transcriptFeed.appendChild(el);
    transcriptFeed.scrollTop = transcriptFeed.scrollHeight;
}

// ── Markdown renderer (lightweight, no deps) ──────────────────────────────────
function renderMarkdown(md, container) {
    let html = md
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        // headings
        .replace(/^### (.+)$/gm, '<h3>$1</h3>')
        .replace(/^## (.+)$/gm, '<h2>$1</h2>')
        .replace(/^# (.+)$/gm, '<h1>$1</h1>')
        // bold
        .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
        .replace(/__(.+?)__/g, '<strong>$1</strong>')
        // italic
        .replace(/\*(.+?)\*/g, '<em>$1</em>')
        // table rows (pipe syntax)
        .replace(/^\|(.+)\|$/gm, (_, row) => {
            const cells = row.split('|').map(c => c.trim());
            const isHeader = cells.every(c => /^-+$/.test(c));
            if (isHeader) return '';
            return '<tr>' + cells.map(c => `<td>${c}</td>`).join('') + '</tr>';
        })
        // bullets
        .replace(/^- (.+)$/gm, '<li>$1</li>')
        // paragraphs
        .replace(/\n{2,}/g, '</p><p>')
        // line breaks
        .replace(/\n/g, '<br>');

    // Wrap bare <tr> in table
    html = html.replace(/(<tr>[\s\S]*?<\/tr>)+/g, m => `<table>${m}</table>`);
    // Wrap <li> in ul
    html = html.replace(/(<li>[\s\S]*?<\/li>)+/g, m => `<ul>${m}</ul>`);

    container.innerHTML = `<div class="notes-body"><p>${html}</p></div>`;
}

// ── UI state helpers ───────────────────────────────────────────────────────────
function setRecordingUI() {
    btnRecord.classList.remove('btn-disabled');
    btnRecord.classList.add('btn-stop');
    btnIcon.textContent = '■';
    btnLabel.textContent = 'Stop Recording';
    timer.style.display = 'flex';
    setStatus('Recording', 'recording');
}

function setIdleUI() {
    btnRecord.classList.remove('btn-stop');
    btnIcon.textContent = '●';
    btnLabel.textContent = 'Start Recording';
    timer.style.display = 'none';
}

function setStatus(text, type) {
    statusText.textContent = text;
    statusDot.className = 'status-dot ' + type;
}

// ── Timer ──────────────────────────────────────────────────────────────────────
function startTimer() {
    stopTimer();
    timerInterval = setInterval(() => {
        const s = Math.floor((Date.now() - startTime) / 1000);
        const m = Math.floor(s / 60).toString().padStart(2, '0');
        const sec = (s % 60).toString().padStart(2, '0');
        timerDisplay.textContent = `${m}:${sec}`;
    }, 1000);
}
function stopTimer() {
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
}

// ── Utilities ──────────────────────────────────────────────────────────────────
function bg(action, data = {}) {
    return chrome.runtime.sendMessage({ action, ...data });
}

function escHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ── Bootstrap ──────────────────────────────────────────────────────────────────
init();
