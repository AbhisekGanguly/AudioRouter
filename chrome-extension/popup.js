// The per-tab control screen. Three groups of rows:
//   1. The active tab — full controls (capture can start here, because
//      opening this popup counts as invoking the extension on it).
//   2. Already-routed tabs — full controls (their sessions live in the
//      offscreen document; no new capture permission needed).
//   3. Other audible tabs — shown for awareness; click to jump there,
//      then reopen the popup to control it.

const $ = (sel) => document.querySelector(sel);

let state = { devices: [], labelsGranted: false, sessions: [] };

function bg(message) {
  return chrome.runtime.sendMessage({ ...message, target: "background" });
}

async function refresh() {
  state = (await bg({ type: "getState" })) ?? state;

  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const allTabs = await chrome.tabs.query({});

  const sessionByTab = new Map(state.sessions.map((s) => [s.tabId, s]));
  const audibleTabs = allTabs.filter(
    (t) => (t.audible || sessionByTab.has(t.id)) && t.id !== activeTab?.id
  );

  $("#grant-banner").classList.toggle("hidden", state.labelsGranted);

  const list = $("#list");
  list.textContent = "";

  if (activeTab && isControllable(activeTab)) {
    list.appendChild(sectionLabel("Current tab"));
    list.appendChild(row(activeTab, sessionByTab.get(activeTab.id), true));
  }

  const routed = audibleTabs.filter((t) => sessionByTab.has(t.id));
  const others = audibleTabs.filter((t) => !sessionByTab.has(t.id));

  if (routed.length > 0) {
    list.appendChild(sectionLabel("Routed tabs"));
    routed.forEach((t) => list.appendChild(row(t, sessionByTab.get(t.id), true)));
  }

  if (others.length > 0) {
    list.appendChild(sectionLabel("Other tabs playing audio"));
    others.forEach((t) => list.appendChild(row(t, undefined, false)));
  }

  if (list.children.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = "Open a tab with audio, then click this icon to route it.";
    list.appendChild(empty);
  }

  $("#status").textContent = `${state.sessions.length} routed tab${state.sessions.length === 1 ? "" : "s"}`;
}

function isControllable(tab) {
  // chrome:// and Web Store pages can't be captured.
  const url = tab.url || "";
  return !url.startsWith("chrome://") && !url.startsWith("https://chromewebstore.google.com");
}

function sectionLabel(text) {
  const el = document.createElement("div");
  el.className = "section-label";
  el.textContent = text;
  return el;
}

function row(tab, session, controllable) {
  const node = $("#row-template").content.firstElementChild.cloneNode(true);
  node.querySelector(".favicon").src = tab.favIconUrl || "icons/icon16.png";
  node.querySelector(".title").textContent = tab.title || "Untitled tab";
  node.querySelector(".audible-badge").classList.toggle("hidden", !tab.audible);

  const subtitle = node.querySelector(".subtitle");
  const controls = node.querySelector(".controls");
  const stopBtn = node.querySelector(".stop");

  if (!controllable) {
    controls.classList.add("hidden");
    subtitle.textContent = "Click to open this tab, then reopen AudioRouter to control it";
    node.classList.add("clickable");
    node.addEventListener("click", async () => {
      await chrome.tabs.update(tab.id, { active: true });
      await chrome.windows.update(tab.windowId, { focused: true });
      window.close();
    });
    return node;
  }

  const select = node.querySelector("select.device");
  fillDeviceSelect(select, session?.sinkId ?? "");

  const slider = node.querySelector("input.volume");
  const volumeLabel = node.querySelector(".volume-label");
  const volumePct = Math.round((session?.volume ?? 1) * 100);
  slider.value = volumePct;
  volumeLabel.textContent = `${volumePct}%`;

  if (session) {
    subtitle.textContent = describeSink(session.sinkId);
    subtitle.classList.add("routed");
    stopBtn.classList.remove("hidden");
  } else {
    subtitle.textContent = "Not routed — pick a device or adjust volume to start";
  }

  select.addEventListener("change", async () => {
    const sinkId = select.value;
    const result = session
      ? await bg({ type: "setSink", tabId: tab.id, sinkId })
      : await bg({ type: "route", tabId: tab.id, sinkId, volume: Number(slider.value) / 100 });
    handleResult(result, subtitle);
    await refresh();
  });

  slider.addEventListener("input", async () => {
    const volume = Number(slider.value) / 100;
    volumeLabel.textContent = `${slider.value}%`;
    if (session) {
      await bg({ type: "setVolume", tabId: tab.id, volume });
      session.volume = volume;
    }
  });

  slider.addEventListener("change", async () => {
    if (!session) {
      const result = await bg({
        type: "route",
        tabId: tab.id,
        sinkId: select.value,
        volume: Number(slider.value) / 100,
      });
      handleResult(result, subtitle);
      await refresh();
    }
  });

  stopBtn.addEventListener("click", async () => {
    await bg({ type: "stop", tabId: tab.id });
    await refresh();
  });

  return node;
}

function fillDeviceSelect(select, selectedSinkId) {
  select.textContent = "";
  const def = document.createElement("option");
  def.value = "";
  def.textContent = "System Default";
  select.appendChild(def);

  for (const d of state.devices) {
    if (d.deviceId === "default") continue; // avoid duplicate default entry
    const opt = document.createElement("option");
    opt.value = d.deviceId;
    opt.textContent = d.label || `Output device (${d.deviceId.slice(0, 8)}…)`;
    select.appendChild(opt);
  }
  select.value = selectedSinkId;
  if (select.value !== selectedSinkId) select.value = "";
}

function describeSink(sinkId) {
  if (!sinkId) return "→ System Default";
  const device = state.devices.find((d) => d.deviceId === sinkId);
  return `→ ${device?.label || "Selected device"}`;
}

function handleResult(result, subtitle) {
  if (result && result.ok === false) {
    subtitle.textContent = `Couldn't start: ${result.error || "unknown error"}`;
    subtitle.classList.remove("routed");
    subtitle.classList.add("error");
  }
}

$("#grant-btn").addEventListener("click", () => chrome.runtime.openOptionsPage());
$("#options-link").addEventListener("click", (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
});

refresh();
