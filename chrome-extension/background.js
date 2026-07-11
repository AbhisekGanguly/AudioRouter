// Background service worker: owns the offscreen document lifecycle, starts
// tab captures (which must originate here via tabCapture.getMediaStreamId),
// relays control messages from the popup to the offscreen audio engine, and
// keeps the action badge in sync with which tabs are routed.

const OFFSCREEN_URL = "offscreen.html";

async function ensureOffscreen() {
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
  });
  if (contexts.length > 0) return;
  await chrome.offscreen.createDocument({
    url: OFFSCREEN_URL,
    reasons: ["USER_MEDIA", "AUDIO_PLAYBACK"],
    justification:
      "Plays captured tab audio through the output device the user chose, with per-tab volume.",
  });
}

function offscreenCall(message) {
  return chrome.runtime.sendMessage({ ...message, target: "offscreen" });
}

function getMediaStreamId(targetTabId) {
  return new Promise((resolve, reject) => {
    chrome.tabCapture.getMediaStreamId({ targetTabId }, (streamId) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(streamId);
      }
    });
  });
}

async function setBadge(tabId, routed) {
  try {
    await chrome.action.setBadgeText({ tabId, text: routed ? "ON" : "" });
    if (routed) {
      await chrome.action.setBadgeBackgroundColor({ tabId, color: "#3f7dfb" });
    }
  } catch {
    // tab may already be gone
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.target !== "background") return;

  (async () => {
    switch (msg.type) {
      case "getState": {
        await ensureOffscreen();
        return await offscreenCall({ type: "getState" });
      }

      // Start (or restart) routing a tab. Requires the extension to have
      // been invoked on that tab (opening the popup on the active tab
      // counts) — otherwise Chrome rejects the capture.
      case "route": {
        await ensureOffscreen();
        const streamId = await getMediaStreamId(msg.tabId);
        const result = await offscreenCall({
          type: "begin",
          tabId: msg.tabId,
          streamId,
          sinkId: msg.sinkId ?? "",
          volume: msg.volume ?? 1,
        });
        if (result?.ok) await setBadge(msg.tabId, true);
        return result;
      }

      case "setVolume":
        return await offscreenCall({ type: "setVolume", tabId: msg.tabId, volume: msg.volume });

      case "setSink":
        return await offscreenCall({ type: "setSink", tabId: msg.tabId, sinkId: msg.sinkId });

      case "stop": {
        const result = await offscreenCall({ type: "end", tabId: msg.tabId });
        await setBadge(msg.tabId, false);
        return result;
      }
    }
  })()
    .then(sendResponse)
    .catch((err) => sendResponse({ ok: false, error: String(err?.message || err) }));

  return true;
});

chrome.tabs.onRemoved.addListener(async (tabId) => {
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
  });
  if (contexts.length === 0) return;
  offscreenCall({ type: "end", tabId }).catch(() => {});
});
