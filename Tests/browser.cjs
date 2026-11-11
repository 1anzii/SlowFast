// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');
const root = path.resolve(__dirname, '..');
const code = fs.readFileSync(path.join(root, 'Resources/video.js'), 'utf8');
const video = fs.readFileSync(path.join(root, '.build/test-video.mp4'));

(async () => {
  const server = http.createServer((request, response) => {
    if (request.url === '/video.mp4') {
      response.writeHead(200, { 'Content-Type': 'video/mp4', 'Content-Length': video.length });
      response.end(video);
    } else { response.setHeader('Content-Type', 'text/html'); response.end('<!doctype html><html lang="zh"><body></body></html>'); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 820 } });
    await page.goto(base);
    const invoke = async (request) => page.evaluate(({ code, request }) => {
      return new Function(`${code};return slowfastControl(arguments[0])`)(request);
    }, { code, request });
    const fixture = async (body) => {
      await page.setContent(body);
      await page.evaluate(async () => {
        await Promise.all([...document.querySelectorAll('video')].map(v => v.readyState ? null : new Promise(r => v.addEventListener('loadedmetadata', r, { once: true }))));
      });
    };
    const tag = (id, style = '') => `<video id="${id}" src="${base}/video.mp4" muted loop preload="auto" style="width:640px;height:360px;${style}"></video>`;
    assert.equal((await invoke({ action: 'faster' })).ok, false);
    await fixture(tag('main'));
    for (const [action, expected] of [['slower', .75], ['slower', .5], ['slower', .5], ['reset', 1], ['faster', 1.25], ['faster', 1.5], ['faster', 2], ['faster', 2]]) {
      assert.equal((await invoke({ action })).rate, expected);
    }
    assert.equal(await page.$eval('#main', v => v.paused), true, 'rate changes must not start playback');
    const probeBeforeStatus = await invoke({ kind: 'probe' });
    const pausedBefore = await page.$eval('#main', v => ({rate:v.playbackRate, time:v.currentTime, paused:v.paused}));
    assert.deepEqual(await invoke({ kind: 'status' }), {ok:true, rate:2, playing:false});
    assert.deepEqual(await page.$eval('#main', v => ({rate:v.playbackRate, time:v.currentTime, paused:v.paused})), pausedBefore, 'status reads never change speed, time or pause');
    assert.equal((await invoke({kind:'apply', token:probeBeforeStatus.token, action:'reset'})).ok, true, 'read-only status must not invalidate extension probes');
    await page.$eval('#main', v => v.playbackRate = 1.7);
    assert.equal((await invoke({ action: 'slower' })).rate, 1.5);
    assert.equal((await invoke({ action: 'set', rate: 42 })).ok, false);
    await page.$eval('#main', v => v.play());
    await invoke({ action: 'set', rate: 2 });
    assert.deepEqual(await invoke({ kind:'status' }), {ok:true, rate:2, playing:true});
    const before = await page.$eval('#main', v => v.currentTime);
    await page.waitForTimeout(500);
    const after = await page.$eval('#main', v => v.currentTime);
    assert.ok(after - before > .7 && after - before < 1.4, 'real video clock runs around 2x');
    assert.equal(await page.$eval('#main', v => v.preservesPitch), true);
    console.log('PASS: real HTML video rates, boundaries, off-grid, pause preservation, 2x media clock');
    console.log('PASS: read-only playback status, paused/playing detection, probe-token preservation');

    await fixture(tag('big') + tag('playing', 'width:320px;height:180px'));
    await page.$eval('#playing', v => v.play());
    await invoke({ action: 'faster' });
    assert.equal(await page.$eval('#playing', v => v.playbackRate), 1.25);
    assert.equal(await page.$eval('#big', v => v.playbackRate), 1);
    const probe = await invoke({ kind: 'probe' });
    await page.$eval('#playing', v => v.remove());
    assert.equal((await invoke({ kind: 'apply', token: probe.token, action: 'faster' })).ok, false);
    console.log('PASS: active video selected; stale probe cannot change a different video');

    await fixture('<div id="host"></div>');
    await page.evaluate(async (src) => {
      const v = document.createElement('video'); v.src = src; v.style.cssText = 'width:640px;height:360px';
      document.querySelector('#host').attachShadow({ mode: 'open' }).append(v);
      await new Promise(r => v.addEventListener('loadedmetadata', r, { once: true }));
    }, `${base}/video.mp4`);
    assert.equal((await invoke({ action: 'faster' })).rate, 1.25);
    console.log('PASS: open Shadow DOM');

    await fixture('<iframe style="width:700px;height:450px"></iframe>');
    await page.evaluate(async (src) => {
      const doc = document.querySelector('iframe').contentDocument;
      const v = doc.createElement('video'); v.src = src; v.style.cssText = 'width:640px;height:360px'; doc.body.append(v);
      await new Promise(r => v.addEventListener('loadedmetadata', r, { once: true }));
    }, `${base}/video.mp4`);
    assert.equal((await invoke({ action: 'faster' })).rate, 1.25);
    assert.equal((await invoke({ kind: 'probe', crossFrames: false })).ok, false);
    console.log('PASS: same-origin frame traversal; extension probes do not double-count child frames');

    await fixture(tag('hidden', 'display:none') + tag('visible'));
    const picked = await invoke({ action: 'faster', toast: true });
    assert.equal(picked.rate, 1.25);
    assert.equal(await page.$eval('#hidden', v => v.playbackRate), 1);
    assert.ok(await page.$('#__slowfast_toast'));
    await page.screenshot({ path: path.join(root, '.build/browser-test.png') });
    console.log('PASS: hidden video ignored; page feedback rendered');

    const popup = await browser.newPage({ viewport: { width: 420, height: 540 } });
    await popup.goto('file://' + path.join(root, 'BrowserExtension/popup.html'));
    await popup.screenshot({ path: path.join(root, '.build/popup-preview.png') });
  } finally {
    await browser.close(); server.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
