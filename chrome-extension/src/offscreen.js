/**
 * offscreen.js — Audio capture + local Whisper transcription
 *
 * Runs in the offscreen document (hidden page, persistent while recording).
 * Captures the Teams tab audio stream, chunks it every 5 seconds,
 * and transcribes each chunk locally using @xenova/transformers (Whisper).
 *
 * Privacy: Audio is processed entirely in memory. No audio bytes leave this device.
 * The Whisper model (whisper-tiny.en, ~40MB) downloads from HuggingFace once,
 * then is permanently cached in your browser's Cache API.
 */

import { pipeline, env } from '@xenova/transformers';

// ── Configure transformers.js for local/extension use ─────────────────────────
// Point ONNX WASM runtime at the files we bundled in dist/wasm/
env.backends.onnx.wasm.wasmPaths = chrome.runtime.getURL('wasm/');
// Cache the model locally in browser's Cache API (not HuggingFace CDN after first load)
env.cacheDir = 'transformers-cache';
env.allowRemoteModels = true;  // needed for first-time model download

// ── State ──────────────────────────────────────────────────────────────────────
let transcriber = null;
let mediaStream = null;
let audioContext = null;
let recorder = null;
let audioChunks = [];
let isCapturing = false;
let chunkTimer = null;

const CHUNK_INTERVAL_MS = 5000;  // process audio every 5 seconds
const SAMPLE_RATE = 16000; // Whisper expects 16kHz

// ── Load Whisper model ─────────────────────────────────────────────────────────
async function loadWhisper() {
    if (transcriber) return transcriber;

    console.log('[offscreen] Loading Whisper model (whisper-tiny.en)...');
    console.log('[offscreen] First load downloads ~40MB from HuggingFace, then caches locally.');

    try {
        transcriber = await pipeline(
            'automatic-speech-recognition',
            'Xenova/whisper-tiny.en',
            {
                progress_callback: (progress) => {
                    if (progress.status === 'downloading') {
                        const pct = Math.round((progress.loaded / progress.total) * 100);
                        chrome.runtime.sendMessage({
                            action: 'modelLoadProgress',
                            progress: pct,
                            file: progress.file,
                        }).catch(() => { });
                    }
                },
            }
        );
        console.log('[offscreen] Whisper model loaded.');
        return transcriber;
    } catch (err) {
        console.error('[offscreen] Failed to load Whisper model:', err);
        throw err;
    }
}

// ── Start audio capture ────────────────────────────────────────────────────────
async function startCapture(streamId) {
    if (isCapturing) return;

    try {
        // Get the tab audio stream using the stream ID from background
        mediaStream = await navigator.mediaDevices.getUserMedia({
            audio: {
                mandatory: {
                    chromeMediaSource: 'tab',
                    chromeMediaSourceId: streamId,
                },
            },
            video: false,
        });

        // Create audio context for resampling
        audioContext = new AudioContext({ sampleRate: SAMPLE_RATE });
        const source = audioContext.createMediaStreamSource(mediaStream);

        // Use a ScriptProcessor to collect PCM samples
        const bufferSize = 4096;
        const processor = audioContext.createScriptProcessor(bufferSize, 1, 1);
        const pcmChunks = [];

        processor.onaudioprocess = (e) => {
            if (!isCapturing) return;
            // Copy PCM float32 data
            pcmChunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
        };

        source.connect(processor);
        processor.connect(audioContext.destination);

        isCapturing = true;
        console.log('[offscreen] Audio capture started.');

        // Pre-load Whisper while first audio chunk is collecting
        loadWhisper().catch(console.error);

        // Process chunks every CHUNK_INTERVAL_MS
        chunkTimer = setInterval(async () => {
            if (!isCapturing || pcmChunks.length === 0) return;

            // Drain current samples
            const samples = mergeFloat32Arrays(pcmChunks.splice(0, pcmChunks.length));

            // Skip silent/very short chunks
            if (samples.length < SAMPLE_RATE) return;    // < 1 second
            if (isVirtuallySilent(samples)) return;

            // Transcribe locally
            const text = await transcribeChunk(samples);
            if (text?.trim()) {
                chrome.runtime.sendMessage({
                    action: 'transcriptChunk',
                    text: text.trim(),
                    timestamp: Date.now(),
                }).catch(() => { });
            }
        }, CHUNK_INTERVAL_MS);

    } catch (err) {
        console.error('[offscreen] startCapture error:', err);
        chrome.runtime.sendMessage({ action: 'captureError', error: err.message }).catch(() => { });
    }
}

// ── Stop capture ───────────────────────────────────────────────────────────────
function stopCapture() {
    isCapturing = false;
    if (chunkTimer) { clearInterval(chunkTimer); chunkTimer = null; }
    if (mediaStream) { mediaStream.getTracks().forEach(t => t.stop()); mediaStream = null; }
    if (audioContext) { audioContext.close(); audioContext = null; }
    console.log('[offscreen] Capture stopped.');
}

// ── Transcribe a Float32Array chunk with Whisper ───────────────────────────────
async function transcribeChunk(samples) {
    try {
        const tw = await loadWhisper();
        const result = await tw(samples, {
            language: 'english',
            task: 'transcribe',
            chunk_length_s: 5,
            stride_length_s: 1,
            return_timestamps: false,
        });
        return result?.text ?? '';
    } catch (err) {
        console.warn('[offscreen] Transcription error:', err);
        return '';
    }
}

// ── Helpers ────────────────────────────────────────────────────────────────────
function mergeFloat32Arrays(arrays) {
    const total = arrays.reduce((sum, a) => sum + a.length, 0);
    const out = new Float32Array(total);
    let offset = 0;
    for (const a of arrays) { out.set(a, offset); offset += a.length; }
    return out;
}

function isVirtuallySilent(samples, threshold = 0.003) {
    // RMS energy check — skip near-silent chunks
    const rms = Math.sqrt(samples.reduce((s, v) => s + v * v, 0) / samples.length);
    return rms < threshold;
}

// ── Message handler ────────────────────────────────────────────────────────────
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.action === 'startCapture') {
        startCapture(msg.streamId).then(() => sendResponse({ ok: true }));
        return true;
    }
    if (msg.action === 'stopCapture') {
        stopCapture();
        sendResponse({ ok: true });
    }
});
