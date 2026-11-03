const photoshop = require("photoshop");
const { entrypoints } = require("uxp");
let running = false;
let busy = false;
let timer = null;
let lastSignature = "";
let lastError = "";
const status = text => { document.getElementById("status").textContent = text; };

const MAC_URL = "http://localhost:48766";
let sessionKey = "";
let lastHandshake = 0;
let lastNetworkError = "";

function unavailable() {
  const error = new Error("等待本机 PSD Mirror，请先打开 Mac 应用；稍后会自动重试。");
  error.macUnavailable = true;
  return error;
}

async function ensureSession(force = false) {
  if (!force && sessionKey && Date.now() - lastHandshake < 3000) return;
  try {
    const response = await fetch(MAC_URL + "/session", {
      headers: {"X-Mirror-Plugin-Client": "psdmirror-uxp"}
    });
    if (!response.ok) throw unavailable();
    const session = await response.json();
    if (session.service !== "psdmirror-plugin" || session.version !== 1 || !/^[a-f0-9]{32}$/i.test(session.key)) {
      throw unavailable();
    }
    if (sessionKey !== session.key) lastSignature = "";
    sessionKey = session.key;
    lastHandshake = Date.now();
  } catch (error) {
    const detail = String(error.message || error);
    if (detail !== lastNetworkError) { console.error("PSD Mirror local connection:", detail); lastNetworkError = detail; }
    sessionKey = ""; lastHandshake = 0;
    throw unavailable();
  }
}

async function push(payload) {
  const request = () => fetch(MAC_URL + "/push", {
    method: "POST",
    headers: {"Content-Type": "application/json", "X-Mirror-Plugin-Client": "psdmirror-uxp", "X-Mirror-Plugin-Key": sessionKey},
    body: JSON.stringify(payload)
  });
  let response;
  try {
    response = await request();
    if (response.status === 401) { await ensureSession(true); response = await request(); }
  } catch (error) { sessionKey = ""; throw unavailable(); }
  if (!response.ok) throw new Error("Mac 未能接收画面（" + response.status + "），稍后自动重试。");
}

function dimension(value) {
  return Math.round(typeof value === "number" ? value : value.value);
}

async function send(force = false) {
  if (busy) return;
  busy = true;
  try {
    await ensureSession();
    const doc = photoshop.app.activeDocument;
    if (!doc || !/\.psd$/i.test(doc.title)) {
      status("请打开一个已命名为 .psd 的 Photoshop 文档。");
      return;
    }
    const width = dimension(doc.width);
    const height = dimension(doc.height);
    const quality = Number(document.getElementById("quality").value) || 4096;
    const history = doc.activeHistoryState;
    const signature = [doc.id, history ? history.id : "unknown", width, height, quality].join(":");
    if (!force && signature === lastSignature) return;
    const longest = Math.max(width, height);
    const targetSize = width >= height ? {width: Math.min(width, quality)} : {height: Math.min(height, quality)};
    const options = {
      documentID: doc.id,
      sourceBounds: {left: 0, top: 0, right: width, bottom: height},
      colorSpace: "RGB",
      colorProfile: "sRGB IEC61966-2.1",
      componentSize: 8,
      applyAlpha: true
    };
    if (longest > quality) options.targetSize = targetSize;
    // Photoshop 25.x requires a modal scope for imaging operations. Keep
    // network transfer outside it so editing is blocked only while reading the composite.
    const payload = await photoshop.core.executeAsModal(async () => {
      let pixels = null;
      try {
        pixels = await photoshop.imaging.getPixels(options);
        const jpeg = await photoshop.imaging.encodeImageData({imageData: pixels.imageData, base64: true});
        return {id: String(doc.id), title: doc.title, width, height, jpeg};
      } finally {
        if (pixels && pixels.imageData) pixels.imageData.dispose();
      }
    }, {commandName: "PSD Mirror 读取预览"});
    await push(payload);
    lastSignature = signature;
    lastError = "";
    status(`已同步 ${doc.title}\n${width} × ${height} · ${new Date().toLocaleTimeString()}`);
  } catch (error) {
    const message = String(error.message || error);
    if (message !== lastError) {
      console.error("PSD Mirror capture failed", error);
      status(error.macUnavailable ? message : "同步失败：" + message + "\n绘画操作结束后会自动重试。");
      lastError = message;
    }
  } finally {
    busy = false;
  }
}

function stop(remember = true) {
  running = false;
  if (remember) localStorage.setItem("mirror-running", "0");
  if (timer) clearInterval(timer);
  timer = null;
  document.getElementById("toggle").textContent = "开始实时同步";
}

function start() {
  if (running) return;
  running = true;
  localStorage.setItem("mirror-running", "1");
  document.getElementById("toggle").textContent = "暂停同步";
  send(true);
  timer = setInterval(() => send(false), 600);
}

function show() {
  if (localStorage.getItem("mirror-running") !== "0") start();
}

document.getElementById("send").addEventListener("click", () => send(true));
document.getElementById("toggle").addEventListener("click", () => {
  if (running) { stop(); status("已暂停同步"); return; }
  start();
});
entrypoints.setup({
  panels: {mirrorPanel: {show, hide() { stop(false); }}},
  commands: {
    startMirror() { start(); },
    stopMirror() { stop(); status("已暂停同步"); }
  }
});
show();
