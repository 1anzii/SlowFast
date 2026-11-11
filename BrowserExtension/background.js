// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

importScripts('video.js');

// Each tab has its own queue; repeated keys cannot race a read / write pair.
const queues = new Map();
async function control(tabId, action, rate) {
  try {
    const frames = await chrome.scripting.executeScript({
      target: { tabId, allFrames: true }, func: slowfastControl,
      args: [{ kind: 'probe', crossFrames: false }],
    });
    const best = frames.filter((frame) => frame.result?.ok).sort((a, b) => b.result.score - a.result.score)[0];
    if (!best) throw new Error('当前标签页没有可控制的视频，请先开始播放');
    const responses = await chrome.scripting.executeScript({
      target: { tabId, frameIds: [best.frameId] }, func: slowfastControl,
      args: [{ kind: 'apply', token: best.result.token, action, rate, toast: true }],
    });
    const result = responses[0]?.result;
    if (!result?.ok) throw new Error(result?.message ?? '视频已切换，请重试');
    await chrome.action.setBadgeText({ tabId, text: `${result.rate}×` });
    await chrome.action.setBadgeBackgroundColor({ tabId, color: '#344a34' });
    return result;
  } catch (error) {
    const message = /Cannot access|Missing host permission|extensions gallery|No tab with id|Frame with ID/i.test(error.message)
      ? '此页面不允许扩展访问；请切换到普通视频网页（本地文件需允许文件访问）' : error.message;
    await chrome.action.setBadgeText({ tabId, text: '!' }).catch(() => {});
    await chrome.scripting.executeScript({
      target: { tabId }, func: slowfastControl, args: [{ kind: 'message', message }],
    }).catch(() => {});
    return { ok: false, message };
  }
}

function enqueue(tabId, action, rate) {
  const previous = queues.get(tabId) ?? Promise.resolve();
  const next = previous.catch(() => {}).then(() => control(tabId, action, rate));
  queues.set(tabId, next);
  next.finally(() => { if (queues.get(tabId) === next) queues.delete(tabId); });
  return next;
}

chrome.commands.onCommand.addListener(async (command, commandTab) => {
  if (!['slower', 'faster', 'reset'].includes(command)) return;
  const tab = commandTab?.id ? commandTab : (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0];
  if (tab?.id) await enqueue(tab.id, command);
});

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  // Only the bundled popup may issue commands. There are no content-script messages.
  if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL('popup.html')) return;
  if (message.type !== 'control' || !['slower', 'faster', 'reset', 'set'].includes(message.action)) return;
  if (message.action === 'set' && ![0.5, 0.75, 1, 1.25, 1.5, 2].includes(message.rate)) return;
  chrome.tabs.query({ active: true, lastFocusedWindow: true }).then(([tab]) => {
    if (!tab?.id) return { ok: false, message: '请先打开视频标签页' };
    return enqueue(tab.id, message.action, message.rate);
  }).then(respond).catch(() => respond({ ok: false, message: '无法连接当前标签页' }));
  return true;
});

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.status === 'loading') chrome.action.setBadgeText({ tabId, text: '' }).catch(() => {});
});
