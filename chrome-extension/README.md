# Ivey Meeting Notes — Chrome Extension

Local AI meeting notes for Microsoft Teams. **100% private — audio never leaves your device.**

## What it does

| Step | How |
|---|---|
| **Capture** | Chrome's `tabCapture` API grabs the Teams tab audio — no screen share needed |
| **Transcribe** | Whisper (whisper-tiny.en) runs as WebAssembly inside the extension |
| **Speaker names** | Read directly from the Teams Web DOM — exact names, no diarization guessing |
| **Summarize** | Ollama (llama3.2) at `127.0.0.1:11434` — your own machine, nothing clouds |
| **Output** | Structured Markdown: Attendees · Decisions · Action Items · Blockers · Next Steps |

## Privacy

```
Teams audio → chrome.tabCapture (in memory)
           → whisper.wasm (local WebAssembly)
           → transcript text
           → Ollama at 127.0.0.1:11434
           → meeting notes (your Downloads folder)

Nothing goes to any external server.
```

The only one-time external download: the Whisper model (~40MB from HuggingFace) on first use. After that, everything runs offline from the browser cache.

## Setup (3 steps)

### 1. Make sure Ollama is running

```powershell
ollama serve          # start the local LLM server
ollama pull llama3.2  # download the model (one-time, ~2GB)
```

### 2. Build the extension

```powershell
cd chrome-extension
npm install
node build.js
```

This produces a `dist/` folder (~37MB including ONNX WASM runtime).

### 3. Load in Chrome

1. Open `chrome://extensions`
2. Enable **Developer mode** (top-right toggle)
3. Click **Load unpacked**
4. Select the `chrome-extension/dist/` folder
5. Pin the extension to your toolbar

## How to use

1. Open a Teams meeting in Chrome (`teams.microsoft.com`)
2. Click the **🎙️ Ivey Meeting Notes** extension icon
3. Click **Start Recording**
4. On first use: Whisper downloads (~40MB, one-time, shows progress bar)
5. Speak! The live transcript appears with colour-coded speaker names
6. Click **Stop Recording** when done
7. Click **✨ Generate Meeting Notes**
8. Download as Markdown or copy to clipboard

## Output format

```markdown
# [Meeting Title]

**Date:** 2026-02-20
**Attendees:** Alex Smith, Jordan Lee, ...

## Summary
...

## Key Decisions
- **Decision** — Owner: Alex Smith

## Action Items
| Owner | Task | Due | Quote |
| --- | --- | --- | --- |
| Jordan Lee | … | TBD | "I'll handle that" |

## Blockers & Risks
- ...

## Next Steps
- ...
```

## Rebuilding after changes

```powershell
cd chrome-extension
node build.js
# Then reload the extension in chrome://extensions → click the refresh icon
```

## Troubleshooting

| Issue | Fix |
|---|---|
| "No Teams tab found" | Navigate to `teams.microsoft.com` and join a meeting first |
| "Could not reach Ollama" | Run `ollama serve` in a terminal |
| Speaker shows "Unknown" | Teams DOM varies — open an issue with your Teams version |
| Whisper slow | First load downloads model; subsequent loads use browser cache |
| Model download fails | Check your internet connection (one-time only) |

## Files

```
chrome-extension/
├── dist/           ← Load this in Chrome (after npm run build)
├── src/
│   ├── background.js   Service worker — coordinates everything
│   ├── content.js      Teams DOM reader — extracts speaker names
│   ├── offscreen.js    Audio capture + Whisper inference
│   ├── popup.js        UI controller
│   └── popup.css       Premium dark theme
├── manifest.json
├── popup.html
├── offscreen.html
├── package.json
└── build.js
```
