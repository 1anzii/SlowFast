// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');
const root = path.resolve(__dirname, '..');
const video = fs.readFileSync(path.join(root, '.build/test-video.mp4'));

(async () => {
  const serve = async () => {
    const server = http.createServer((request, response) => {
      response.setHeader('Content-Type', request.url === '/video.mp4' ? 'video/mp4' : 'text/html');
      response.end(request.url === '/video.mp4' ? video : '<!doctype html><html><body></body></html>');
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    return server;
  };
  const servers = await Promise.all([serve(), serve()]);
  const [topURL, childURL] = servers.map(s => `http://127.0.0.1:${s.address().port}`);
  const extension = path.join(root, 'dist/BrowserExtension');
  const useInstalled = process.env.CHROME_PATH;
  const context = await chromium.launchPersistentContext(path.join(root, '.build/extension-test-profile'), {
    ...(useInstalled ? { executablePath: useInstalled } : { channel: 'chromium' }), headless: true,
    args: useInstalled ? ['--enable-unsafe-extension-debugging'] : [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`],
    ignoreDefaultArgs: ['--disable-extensions'],
  });
  try {
    if (useInstalled) {
      const session = await context.browser().newBrowserCDPSession();
      await session.send('Extensions.loadUnpacked', { path: extension });
    }
    const worker = context.serviceWorkers()[0] ?? await context.waitForEvent('serviceworker', { timeout: 10000 });
    const errors = [];
    worker.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    const page = await context.newPage();
    await page.goto(topURL);
    await page.setContent(`<video id="top" muted loop style="width:640px;height:360px" src="${topURL}/video.mp4"></video><iframe src="${childURL}" style="width:700px;height:430px"></iframe>`);
    await page.waitForFunction(() => document.querySelector('video').readyState > 0);
    await page.waitForFunction(() => document.querySelector('iframe').contentWindow !== null);
    let frame;
    for (let i = 0; i < 100; i++) {
      frame = page.frames().find(f => f.url().startsWith(childURL));
      if (frame) break;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert.ok(frame, 'cross-origin child frame loaded');
    await frame.setContent(`<video id="embedded" muted loop style="width:640px;height:360px" src="${childURL}/video.mp4"></video>`);
    await frame.waitForFunction(() => document.querySelector('video').readyState > 0);
    await frame.$eval('video', v => v.play());
    const tabId = await worker.evaluate(async () => (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0].id);
    const run = (action, rate) => worker.evaluate(({tabId, action, rate}) => enqueue(tabId, action, rate), {tabId, action, rate});
    const result = await run('faster');
    assert.equal(result.rate, 1.25);
    assert.equal(await frame.$eval('video', v => v.playbackRate), 1.25);
    assert.equal(await page.$eval('video', v => v.playbackRate), 1);
    assert.equal(await worker.evaluate(tabId => chrome.action.getBadgeText({tabId}), tabId), '1.25×');
    console.log('PASS: real MV3 extension loads, controls cross-origin frame, changes only selected video, confirms badge');

    await run('reset');
    const queued = await worker.evaluate(tabId => Promise.all([enqueue(tabId, 'faster'), enqueue(tabId, 'faster'), enqueue(tabId, 'faster')]), tabId);
    assert.deepEqual(queued.map(r => r.rate), [1.25, 1.5, 2]);
    console.log('PASS: rapid commands are serialized and reach 2x');

    // Headless CDP key injection does not exercise macOS's native shortcut path.
    // Verify registration here; Fn → native event → browser must be tested on hardware.
    const commands = await worker.evaluate(() => chrome.commands.getAll());
    for (const name of ['slower', 'faster', 'reset']) {
      assert.ok(commands.find(command => command.name === name)?.shortcut, `shortcut assigned: ${name}`);
    }
    console.log('PASS: browser accepts and assigns all three command shortcuts', commands);

    await page.goto('about:blank');
    const denied = await run('faster');
    assert.equal(denied.ok, false);
    console.log('PASS: restricted browser page fails explicitly');
    assert.deepEqual(errors, []);
  } finally {
    await context.close(); servers.forEach(s => s.close());
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
