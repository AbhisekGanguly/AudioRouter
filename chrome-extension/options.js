const status = document.getElementById("status");

async function updateStatus() {
  const devices = await navigator.mediaDevices.enumerateDevices();
  const granted = devices.some((d) => d.kind === "audiooutput" && d.label);
  if (granted) {
    status.textContent = "✓ Device access granted — output device names are visible.";
    status.className = "status ok";
    document.getElementById("grant").disabled = true;
  }
}

document.getElementById("grant").addEventListener("click", async () => {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach((t) => t.stop()); // release immediately
    await updateStatus();
  } catch (err) {
    status.textContent = `Access denied: ${err.message}. Check Chrome's site settings for this extension.`;
    status.className = "status err";
  }
});

updateStatus();
