const photoshop = require("photoshop");
const { entrypoints } = require("uxp");
let running = false;
let busy = false;
let timer = null;
let lastSignature = "";
let lastArtboard = null;
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

async function push(payload, path = "/push") {
  const request = () => fetch(MAC_URL + path, {
    method: "POST",
    headers: {"Content-Type": "application/json", "X-Mirror-Plugin-Client": "psdmirror-uxp", "X-Mirror-Plugin-Key": sessionKey},
    body: JSON.stringify(payload)
  });
  let response;
  try {
    response = await request();
    if (response.status === 401) { await ensureSession(true); response = await request(); }
  } catch (error) { sessionKey = ""; throw unavailable(); }
  if (response.status === 404 && path !== "/push") throw new Error("请更新 Mac 端 PSD Mirror 以同步画板。");
  if (!response.ok) throw new Error("Mac 未能接收画面（" + response.status + "），稍后自动重试。");
  return response.json();
}

function dimension(value) {
  return Math.round(typeof value === "number" ? value : value?._value ?? value?.value);
}

function selectedArtboard(doc, boards) {
  const ids = new Set(boards.map(board => board.id));
  for (const selected of Array.from(doc.activeLayers)) {
    for (let layer = selected; layer; layer = layer.parent) {
      if (ids.has(layer.id)) return layer.id;
    }
  }
  if (lastArtboard?.documentID === String(doc.id) && ids.has(lastArtboard.layerID)) return lastArtboard.layerID;
  return boards[0].id;
}

async function artboardBounds(docID, boards) {
  const descriptors = await photoshop.action.batchPlay(boards.map(board => ({
    _obj: "get",
    _target: [{_property: "artboard"}, {_ref: "layer", _id: board.id}, {_ref: "document", _id: docID}]
  })), {});
  return descriptors.map((descriptor, index) => {
    const rect = descriptor.artboard?.artboardRect;
    const bounds = {left: dimension(rect?.left), top: dimension(rect?.top), right: dimension(rect?.right), bottom: dimension(rect?.bottom)};
    if (!Object.values(bounds).every(Number.isFinite) || bounds.right <= bounds.left || bounds.bottom <= bounds.top) {
      throw new Error("无法读取画板范围：" + boards[index].name);
    }
    return bounds;
  });
}

async function capture(doc, bounds, quality, historyID) {
  const width = bounds.right - bounds.left;
  const height = bounds.bottom - bounds.top;
  const options = {
    documentID: doc.id, sourceBounds: bounds, colorSpace: "RGB", colorProfile: "sRGB IEC61966-2.1",
    componentSize: 8, applyAlpha: true
  };
  if (Math.max(width, height) > quality) options.targetSize = width >= height ? {width: quality} : {height: quality};
  // Keep the modal scope to one image so editing can resume between boards.
  return photoshop.core.executeAsModal(async () => {
    if (photoshop.app.activeDocument?.id !== doc.id || doc.activeHistoryState?.id !== historyID) {
      const error = new Error("文档已变化"); error.staleCapture = true; throw error;
    }
    const pixels = await photoshop.imaging.getPixels(options);
    try {
      const jpeg = await photoshop.imaging.encodeImageData({imageData: pixels.imageData, base64: true});
      return {id: String(doc.id), title: doc.title, width, height, jpeg};
    } finally { pixels.imageData.dispose(); }
  }, {commandName: "PSD Mirror 读取预览"});
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
    const historyID = doc.activeHistoryState?.id;
    const boards = Array.from(doc.artboards).map(board => ({id: board.id, name: board.name}));
    const signature = JSON.stringify([doc.id, doc.title, historyID, width, height, quality, boards]);
    const refreshImages = force || signature !== lastSignature;
    if (!boards.length) {
      if (!refreshImages) return;
      await push(await capture(doc, {left: 0, top: 0, right: width, bottom: height}, quality, historyID));
      lastArtboard = null;
      status(`已同步 ${doc.title}\n${width} × ${height} · ${new Date().toLocaleTimeString()}`);
    } else {
      const documentID = String(doc.id);
      const layerID = selectedArtboard(doc, boards);
      if (!refreshImages && lastArtboard?.layerID === layerID && lastArtboard?.documentID === documentID) return;
      if (boards.length > 64) throw new Error("此 PSD 超过 64 个画板的同步上限。");
      const selection = {documentID, layerIDs: boards.map(board => board.id), activeLayerID: layerID};
      let state = await push(selection, "/artboards");
      if (refreshImages || state.missingLayerIDs.length) {
        const pending = refreshImages ? boards : boards.filter(board => state.missingLayerIDs.includes(board.id));
        pending.sort((a, b) => Number(b.id === layerID) - Number(a.id === layerID));
        const bounds = await artboardBounds(doc.id, pending);
        for (let i = 0; i < pending.length; i++) {
          const board = pending[i];
          const document = await capture(doc, bounds[i], quality, historyID);
          await push({document, layerID: board.id, name: board.name || "画板 " + board.id}, "/artboard");
          if (board.id === layerID) await push(selection, "/artboards");
        }
        state = await push(selection, "/artboards");
      }
      lastArtboard = {documentID, layerID};
      status(state.missingLayerIDs.length
        ? `已同步 ${boards.length - state.missingLayerIDs.length}/${boards.length} 个画板。请降低清晰度后重新发送。`
        : `已同步 ${doc.title} · ${boards.length} 个画板\n当前：${boards.find(board => board.id === layerID).name}`);
    }
    lastSignature = signature;
    lastError = "";
  } catch (error) {
    if (error.staleCapture) return;
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
