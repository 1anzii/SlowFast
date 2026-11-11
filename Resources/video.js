// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

// Self-contained so Chromium can serialize it with scripting.executeScript.
function slowfastControl(request) {
  const steps = [0.5, 0.75, 1, 1.25, 1.5, 2];
  const fail = (message) => ({ ok: false, message });
  const toast = (message) => {
    const doc = document;
    const old = doc.getElementById('__slowfast_toast');
    if (old) old.remove();
    const host = doc.createElement('div');
    host.id = '__slowfast_toast';
    host.style.cssText = 'position:fixed!important;bottom:8vh!important;left:50%!important;transform:translateX(-50%)!important;z-index:2147483647!important;pointer-events:none!important;';
    const root = host.attachShadow({ mode: 'closed' });
    const label = doc.createElement('div');
    label.style.cssText = 'background:#192821ef;color:#e4f9ab;border:1px solid #597146;border-radius:18px;padding:16px 26px;font:600 20px -apple-system,system-ui,sans-serif;box-shadow:0 12px 40px #0005;white-space:nowrap';
    label.textContent = message;
    label.setAttribute('role', 'status');
    root.append(label);
    const container = doc.fullscreenElement;
    // A video element cannot render children; show over the document in that case.
    (container && container.tagName !== 'VIDEO' ? container : doc.documentElement).append(host);
    setTimeout(() => host.remove(), 1800);
  };
  if (request.kind === 'message') { toast(request.message); return { ok: true }; }
  const state = globalThis.__slowfastVideoState ??= { target: null, token: null };
  let video;
  let score = 0;
  let blockedFrames = 0;
  if (request.kind === 'apply') {
    if (state.token !== request.token || !state.target?.isConnected) return fail('视频已切换，请再按一次快捷键');
    video = state.target;
  } else {
    const videos = [];
    const visited = new Set();
    function collect(root, parentVisible = true) {
      if (visited.has(root) || !parentVisible) return;
      visited.add(root);
      for (const element of root.querySelectorAll('*')) {
        if (element.tagName === 'VIDEO') videos.push(element);
        if (element.shadowRoot) collect(element.shadowRoot);
        if (element.tagName === 'IFRAME' && request.crossFrames !== false) {
          try {
            const rect = element.getBoundingClientRect();
            const child = element.contentDocument;
            if (child) collect(child, rect.width > 0 && rect.height > 0);
            else blockedFrames++;
          } catch { blockedFrames++; }
        }
      }
    }
    collect(document);
    const candidates = videos.map((v) => {
      const doc = v.ownerDocument;
      const win = doc.defaultView;
      const rect = v.getBoundingClientRect();
      const style = win.getComputedStyle(v);
      const pip = doc.pictureInPictureElement === v || v.webkitPresentationMode === 'picture-in-picture';
      const visible = rect.width > 1 && rect.height > 1 && style.visibility !== 'hidden' && style.display !== 'none' && Number(style.opacity) > 0;
      const inViewport = visible && rect.bottom > 0 && rect.right > 0 && rect.top < win.innerHeight && rect.left < win.innerWidth;
      const fullscreen = doc.fullscreenElement === v || doc.fullscreenElement?.contains(v) || v.webkitDisplayingFullscreen;
      const playing = !v.paused && !v.ended;
      const loaded = !!(v.currentSrc || v.srcObject || v.querySelector('source')) && v.readyState > 0;
      const weight = (pip ? 1e10 : 0) + (fullscreen ? 1e9 : 0) + (playing ? 1e8 : 0) + (inViewport ? 1e7 : 0) + Math.min(rect.width * rect.height, 1e6);
      return { video: v, score: weight, usable: loaded && (visible || pip || playing) };
    }).filter((v) => v.usable).sort((a, b) => b.score - a.score);
    if (!candidates.length) return fail(blockedFrames ? '检测到跨站嵌入视频，请使用 SlowFast 浏览器扩展' : '当前页面没有可控制的视频，请先打开并播放视频');
    ({ video, score } = candidates[0]);
    if (request.kind === 'probe') {
      state.target = video;
      state.token = `${Date.now()}-${Math.random()}`;
      return { ok: true, token: state.token, score, rate: video.playbackRate };
    }
    if (request.kind === 'status') {
      return { ok: true, rate: video.playbackRate, playing: !video.paused && !video.ended };
    }
  }
  const current = video.playbackRate > 0 ? video.playbackRate : 1;
  let rate;
  if (request.action === 'slower') rate = [...steps].reverse().find((v) => v < current - 0.001) ?? steps[0];
  else if (request.action === 'faster') rate = steps.find((v) => v > current + 0.001) ?? steps.at(-1);
  else if (request.action === 'reset') rate = 1;
  else if (request.action === 'set' && steps.includes(request.rate)) rate = request.rate;
  else return fail('无效的倍速指令');
  try {
    video.preservesPitch = true;
    video.playbackRate = rate;
    if (Math.abs(video.playbackRate - rate) > 0.01) return fail('播放器拒绝了倍速设置');
    if (request.toast) toast(`SlowFast  ·  ${rate}×`);
    return { ok: true, rate: video.playbackRate, score, playing: !video.paused && !video.ended };
  } catch { return fail('当前视频不允许修改倍速（可能是直播或受限播放器）'); }
}
