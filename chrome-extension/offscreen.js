// Offscreen audio engine. One capture session per routed tab:
//   tab audio (tabCapture stream) → MediaStreamSource → GainNode → destination
// with AudioContext.setSinkId() aiming the whole graph at the chosen output
// device. Capturing a tab silences its normal output, so whatever we play
// here is the ONLY place the tab's audio comes out — volume and routing in
// one path. When a session ends (stream stopped / tab closed), Chrome
// restores the tab's normal audio automatically.

const sessions = new Map(); // tabId -> { stream, ctx, source, gain, sinkId, volume }

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.target !== "offscreen") return;

  switch (msg.type) {
    case "begin":
      begin(msg.tabId, msg.streamId, msg.sinkId ?? "", msg.volume ?? 1)
        .then(() => sendResponse({ ok: true }))
        .catch((err) => sendResponse({ ok: false, error: String(err?.message || err) }));
      return true;

    case "setVolume": {
      const s = sessions.get(msg.tabId);
      if (s) {
        s.volume = msg.volume;
        s.gain.gain.value = msg.volume;
      }
      sendResponse({ ok: !!s });
      return;
    }

    case "setSink": {
      const s = sessions.get(msg.tabId);
      if (!s) {
        sendResponse({ ok: false, error: "no session" });
        return;
      }
      s.ctx
        .setSinkId(msg.sinkId ?? "")
        .then(() => {
          s.sinkId = msg.sinkId ?? "";
          sendResponse({ ok: true });
        })
        .catch((err) => sendResponse({ ok: false, error: String(err?.message || err) }));
      return true;
    }

    case "end":
      end(msg.tabId);
      sendResponse({ ok: true });
      return;

    case "getState":
      getState().then(sendResponse);
      return true;
  }
});

async function begin(tabId, streamId, sinkId, volume) {
  end(tabId); // replace any existing session for this tab

  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      mandatory: {
        chromeMediaSource: "tab",
        chromeMediaSourceId: streamId,
      },
    },
  });

  const ctx = new AudioContext();
  const source = ctx.createMediaStreamSource(stream);
  const gain = ctx.createGain();
  gain.gain.value = volume;
  source.connect(gain).connect(ctx.destination);

  if (sinkId) {
    await ctx.setSinkId(sinkId);
  }
  if (ctx.state === "suspended") {
    await ctx.resume();
  }

  // If the capture ends for any reason (tab closed, capture revoked),
  // clean up so getState stays truthful.
  stream.getAudioTracks().forEach((track) => {
    track.addEventListener("ended", () => end(tabId));
  });

  sessions.set(tabId, { stream, ctx, source, gain, sinkId, volume });
}

function end(tabId) {
  const s = sessions.get(tabId);
  if (!s) return;
  s.stream.getTracks().forEach((t) => t.stop());
  s.ctx.close().catch(() => {});
  sessions.delete(tabId);
}

async function getState() {
  let devices = [];
  let labelsGranted = false;
  try {
    const all = await navigator.mediaDevices.enumerateDevices();
    devices = all
      .filter((d) => d.kind === "audiooutput")
      .map((d) => ({ deviceId: d.deviceId, label: d.label }));
    labelsGranted = devices.some((d) => d.label && d.label.length > 0);
  } catch {
    // leave devices empty
  }
  return {
    devices,
    labelsGranted,
    sessions: [...sessions.entries()].map(([tabId, s]) => ({
      tabId,
      sinkId: s.sinkId,
      volume: s.volume,
    })),
  };
}
