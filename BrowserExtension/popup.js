// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

const buttons = [...document.querySelectorAll('button')];
buttons.forEach((button) => button.addEventListener('click', async () => {
  buttons.forEach((item) => item.disabled = true);
  const status = document.querySelector('#status');
  status.textContent = '正在连接视频…';
  try {
    const rate = Number(button.dataset.rate);
    const result = await chrome.runtime.sendMessage({ type: 'control', action: button.dataset.action ?? 'set', rate });
    if (!result?.ok) throw new Error(result?.message ?? '没有收到播放器响应');
    document.querySelector('#speed').replaceChildren(document.createTextNode(String(result.rate)), Object.assign(document.createElement('small'), { textContent: '×' }));
    status.textContent = '已调整当前视频';
    buttons.forEach((item) => item.setAttribute('aria-pressed', String(Number(item.dataset.rate) === result.rate)));
  } catch (error) { status.textContent = error.message; }
  finally { buttons.forEach((item) => item.disabled = false); }
}));
