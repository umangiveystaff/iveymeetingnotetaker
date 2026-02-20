/**
 * content.js — Teams DOM speaker detector
 *
 * Injected into teams.microsoft.com. Reads the active speaker's name from
 * the Teams Web UI and reports it to the background service worker.
 *
 * Privacy: only reads DOM — no network calls.
 */

// ── Speaker detection strategies ───────────────────────────────────────────────
// Teams changes its DOM frequently. We try multiple selectors in order.
const SPEAKER_SELECTORS = [
    // Primary: active speaker tile in the meeting stage
    '[data-is-speaking="true"] [data-tid="speaking-participant-name"]',
    '[data-is-speaking="true"] .ui-label',
    '[data-is-speaking="true"] [class*="participant-name"]',
    '[data-is-speaking="true"] [class*="displayName"]',

    // Secondary: active speaker indicator in participant roster
    '[class*="activeSpeaker"] [class*="participantName"]',
    '[class*="activeSpeaker"] .fui-Text',
    '[class*="active-speaker"] [class*="name"]',

    // Tertiary: calling stage dominant speaker
    '[data-tid="calling-dominant-speaker"] [data-tid="participant-name"]',
    '[data-tid="calling-dominant-speaker"] .ui-label',
    '[data-tid="calling-dominant-speaker"] [class*="displayName"]',

    // Quaternary: video tiles with speaking indicator
    '[class*="speaking"] [class*="participantName"]',
    '[class*="speaking"] [class*="displayName"]',
    '[class*="speaking-border"] ~ * [class*="name"]',

    // Teams 2.0 / new Teams
    '[data-component-type="callingParticipant"][aria-label*="speaking"] [class*="nameLabel"]',
    '[class*="dominantSpeaker"] span[class*="text"]',
];

// ── Self participant detection ─────────────────────────────────────────────────
function getSelfName() {
    // Teams usually shows "You" or the logged-in user's name on the self-tile
    const selfSelectors = [
        '[data-tid="calling-participant-stream-mine"] [data-tid="participant-name"]',
        '[class*="self"] [class*="participantName"]',
        '[class*="selfVideo"] [class*="displayName"]',
    ];
    for (const sel of selfSelectors) {
        const el = document.querySelector(sel);
        if (el?.textContent?.trim()) return el.textContent.trim();
    }
    return null;
}

// ── Get current active speaker name ───────────────────────────────────────────
function getActiveSpeaker() {
    for (const selector of SPEAKER_SELECTORS) {
        try {
            const el = document.querySelector(selector);
            if (el) {
                const name = el.textContent?.trim();
                if (name && name.length > 0 && name.length < 80) {
                    return name;
                }
            }
        } catch (_) { /* ignore invalid selectors */ }
    }

    // Fallback: look for any element with aria-live that announces a speaker  
    const liveRegions = document.querySelectorAll('[aria-live]');
    for (const el of liveRegions) {
        const text = el.textContent?.trim();
        if (text && text.includes('speaking') && text.length < 100) {
            // Extract name before "is speaking" pattern
            const match = text.match(/^(.+?)\s+(?:is\s+)?speaking/i);
            if (match?.[1]) return match[1].trim();
        }
    }

    return null;
}

// ── Watch for meeting start ────────────────────────────────────────────────────
function isMeetingActive() {
    return !!(
        document.querySelector('[data-tid="calling-participant-stream"]') ||
        document.querySelector('[class*="callingScreen"]') ||
        document.querySelector('[class*="meetingStage"]') ||
        document.querySelector('[id*="meeting-stage"]') ||
        document.querySelector('[class*="call-stage"]')
    );
}

// ── Polling loop ───────────────────────────────────────────────────────────────
let lastReportedSpeaker = null;
let pollInterval = null;

function startPolling() {
    if (pollInterval) return;
    console.log('[Ivey] Teams content script started — watching for speakers');

    pollInterval = setInterval(() => {
        if (!isMeetingActive()) return;

        const speaker = getActiveSpeaker();
        if (speaker && speaker !== lastReportedSpeaker) {
            lastReportedSpeaker = speaker;
            chrome.runtime.sendMessage({
                action: 'speakerUpdate',
                speakerName: speaker,
                timestamp: Date.now(),
            }).catch(() => { /* SW may be sleeping, fine */ });
        }
    }, 500);
}

function stopPolling() {
    if (pollInterval) {
        clearInterval(pollInterval);
        pollInterval = null;
    }
}

// ── MutationObserver for DOM changes ──────────────────────────────────────────
// This catches when the Teams DOM is ready (SPA, may load after content script)
const observer = new MutationObserver((mutations) => {
    if (isMeetingActive() && !pollInterval) {
        startPolling();
    }
});

observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['data-is-speaking', 'class', 'aria-label'],
});

// Start immediately if meeting is already active
if (isMeetingActive()) startPolling();

// Listen for page unload
window.addEventListener('beforeunload', stopPolling);
