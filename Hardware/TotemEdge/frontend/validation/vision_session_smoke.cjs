/* Existing official UI, real HTTP orchestration, controlled JPEG and providers. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawn } = require('node:child_process');
const { chromium, launchOptions } = require('./browser_tools.cjs');
const { openApprovedVisual, time } = require('./approved_visual.cjs');
const frontend = path.resolve(__dirname, '..'), backend = path.resolve(frontend, '../backend');
const python = process.env.BINGO_TEST_PYTHON || path.join(backend, process.platform === 'win32' ? '.venv/Scripts/python.exe' : '.venv/bin/python');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function main(scenario = 'recognized') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bingo-vision-ui-'));
  assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
  const output = path.join(frontend, '.validation'); fs.mkdirSync(output, { recursive: true });
  const control = data => fs.writeFileSync(path.join(root, 'control.json'), JSON.stringify(data));
  const outcome = scenario === 'rejected' ? { reject: true } : scenario === 'failure' ? { vision_failure: true } : scenario === 'fallback' ? { fallback: true } : {};
  control({ hold_capture: true, ...outcome });
  const reserve = http.createServer(); await new Promise(resolve => reserve.listen(0, '127.0.0.1', resolve));
  const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
  const origin = `http://127.0.0.1:${port}`;
  const env = { ...process.env };
  for (const key of Object.keys(env)) if (/^(BINGO_|SUPABASE_|AWS_|GEMINI_|GOOGLE_)/i.test(key) || /^(https?_proxy|all_proxy|no_proxy)$/i.test(key)) delete env[key];
  const requests = [], errors = [], results = [], visualChecks = [];
  let server, closed, stopped = false, browser, visual, logs = '', report;
  const pass = label => { results.push(label); console.log('PASS: ' + label); };
  const request = async (route, body) => {
    const r = await fetch(origin + route, { method: body === undefined ? 'GET' : 'POST', headers: { 'X-Totem-Request': '1', 'Content-Type': 'application/json' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    assert.ok(r.ok, `Local HTTP ${r.status}`); return r.json();
  };
  const active = async () => (await request('/local/simulation/sessions/active')).snapshot;
  const stats = () => JSON.parse(fs.readFileSync(path.join(root, 'stats.json')));
  try {
    server = spawn(python, ['-B', 'tests/dev_frontend_fixture.py', '--root', root, '--port', String(port), '--vision'], { cwd: backend, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    closed = new Promise(resolve => server.once('close', () => { stopped = true; resolve(); }));
    server.stdout.on('data', b => { logs += b; }); server.stderr.on('data', b => { logs += b; });
    let ready = false, lastProbe;
    for (let i = 0; i < 80; i++) {
      try {
        const response = await fetch(origin + '/health', { headers: { Connection: 'close' }, cache: 'no-store' });
        lastProbe = { status: response.status, body: await response.json() };
        ready = response.ok && lastProbe.body.status === 'ok';
      } catch (error) { lastProbe = { error: error.cause?.code || error.name }; }
      if (ready || stopped) break; await pause(100);
    }
    assert.ok(ready, 'Owned synthetic fixture ready: ' + JSON.stringify(lastProbe));
    browser = await chromium.launch({ ...launchOptions, args: [...(launchOptions.args || []), '--disable-gpu', '--force-color-profile=srgb', '--force-device-scale-factor=1', '--run-all-compositor-stages-before-draw', '--disable-threaded-animation', '--disable-partial-raster'] });
    const context = await browser.newContext({ viewport: { width: 600, height: 1024 }, deviceScaleFactor: 1 });
    const page = await context.newPage();
    await page.route('**/*', route => { assert.equal(new URL(route.request().url()).origin, origin); return route.continue(); });
    page.on('pageerror', e => errors.push(e.message));
    page.on('request', r => { const u = new URL(r.url()); requests.push({ method: r.method(), path: u.pathname }); assert.ok(!u.searchParams.has('pin')); assert.equal(r.headers().authorization, undefined); });
    await page.clock.install({ time }); await page.clock.pauseAt(new Date(time.getTime() + 60000));
    const data = await request('/local/dev/context');
    visual = await openApprovedVisual(context, output, data);
    const click = (op, value) => page.locator(`button[data-dev-op="${op}"]${value ? `[data-value="${value}"]` : ''}`).click();
    const pin = async () => { for (const n of '0012') await click('pin', n); await click('pin', 'OK'); };
    const waitState = async state => {
      for (let i = 0; i < 100; i++) {
        if (await page.locator(`#kiosk[data-operational-state="${state}"]`).count()) return;
        await page.clock.runFor(550); await pause(50);
      }
      throw new Error('UI did not recover durable state ' + state);
    };
    await page.goto(origin); await click('wake'); await click('begin'); await click('mode', 'student');
    await click('segment', data.classes[0].segment); await click('grade', data.classes[0].grade);
    await click('class', data.classes[0].id); await click('student', data.students[0].id); await pin();
    await waitState('SAFETY'); await click('safety', 'safe'); await pin(); await waitState('DOOR_OPEN');
    assert.equal(stats().camera.length, 0, 'No capture before durable closure');
    await click('inserted');
    await page.evaluate(() => { document.querySelector('[data-dev-op="hand"]').click(); document.querySelector('[data-dev-op="hand"]')?.click(); });
    await waitState('CAPTURING');
    assert.equal(stats().primary, 0);
    const beforeReload = requests.filter(r => r.method === 'POST').length;
    await page.reload(); await waitState('CAPTURING');
    assert.equal(requests.filter(r => r.method === 'POST').length, beforeReload);
    assert.equal(stats().camera.length, 1);
    pass('Fechamento durável, clique duplo e refresh durante captura: uma única intenção');
    control({ ...outcome, hold_classification: true, hold_secondary: scenario === 'fallback' });
    await page.reload(); await waitState('CAPTURING');
    for (let i = 0; i < 100 && !await page.locator('[data-camera-canvas][data-loaded="true"]').count(); i++) { await page.clock.runFor(550); await pause(50); }
    await page.locator('[data-camera-canvas][data-loaded="true"]').waitFor();
    const pending = await active();
    const photoUrl = `${origin}/local/simulation/sessions/${pending.session.event_id}/vision-image/${pending.vision.capture_id}`;
    const jpeg = await fetch(photoUrl, { headers: { 'X-Totem-Request': '1' } });
    assert.ok(jpeg.ok);
    const cameraPhoto = 'data:image/jpeg;base64,' + Buffer.from(await jpeg.arrayBuffer()).toString('base64');
    if (scenario === 'recognized') await visual.compare(page, 'camera', { name: 'vision-photo', visionRemote: true, cameraPhoto });
    assert.equal(stats().primary, 0, 'Rendering/refresh/photo GET never classify');
    assert.equal(stats().camera.length, 1);
    assert.equal(await page.locator('[data-camera-video]').evaluate(video => video.srcObject), null);
    assert.ok(await page.locator('[data-camera-retake]').isDisabled());
    await page.evaluate(() => { document.querySelector('[data-dev-op="vision-analyze"]').click(); document.querySelector('[data-dev-op="vision-analyze"]')?.click(); });
    if (!['recognized', 'fallback'].includes(scenario)) {
      control(outcome);
      const state = scenario === 'rejected' ? 'RETURN_REQUIRED' : 'TECHNICAL_FAILURE';
      await waitState(state);
      await visual.compare(page, scenario === 'rejected' ? 'rejected' : 'vision-error', { name: `vision-${scenario}`, visionRemote: true, origin: scenario === 'rejected' ? 'AWS_REKOGNITION' : 'VISION_CASCADE_ERROR', disableReturn: true });
      const snap = await active();
      assert.deepEqual(snap.allowed_actions, []); assert.equal(snap.session.receipt, null);
      assert.equal(stats().primary, 1); assert.equal(stats().secondary, 0);
      const posts = requests.filter(r => r.method === 'POST').length;
      await page.reload(); await waitState(state);
      assert.equal(requests.filter(r => r.method === 'POST').length, posts);
      assert.equal(stats().camera.length, 1); assert.equal(stats().primary, 1);
      assert.ok(requests.every(r => !/hatch|vision-review|register|deposit/.test(r.path)));
      assert.deepEqual(errors, []);
      assert.ok(visual.results.every(r => r.passed), 'Negative flow approved UI regression');
      pass(`${state}: orientação existente, GET sem efeitos e nenhum alçapão/fallback operacional`);
    } else {
    await waitState('CLASSIFYING');
    // The UI clock is paused: keep its genuine CLASSIFYING snapshot for the
    // comparison, but release the provider before its unchanged 10s deadline.
    control({ ...outcome, hold_secondary: scenario === 'fallback' });
    if (scenario === 'fallback') {
      for (let i = 0; i < 30 && !await page.locator('.analysis-progress--secondary').count(); i++) { await page.clock.runFor(550); await pause(50); }
      control(outcome);
      await visual.compare(page, 'secondary-analysis', { name: 'vision-secondary', visionRemote: true });
    } else await visual.compare(page, 'classification', { name: 'vision-classifying', visionRemote: true });
    control(outcome); await waitState('REVIEW');
    const event = (await active()).session.event_id;
    await visual.compare(page, 'recognized', { name: scenario === 'fallback' ? 'vision-fallback-result' : 'vision-suggestion', visionRemote: true, origin: scenario === 'fallback' ? 'GEMINI_FALLBACK' : 'AWS_REKOGNITION', itemId: scenario === 'fallback' ? 'battery' : 'cable' });
    assert.equal(stats().jpeg_delivered, true); assert.equal(stats().primary, 1); assert.equal(stats().secondary, scenario === 'fallback' ? 1 : 0);
    if (scenario === 'fallback') {
      await click('recognition-confirm'); await page.locator('.screen--review').waitFor();
      assert.equal((await active()).vision.decision.source, 'AI_CONFIRMED');
    } else {
    await click('correction');
    await visual.compare(page, 'correct-item', { name: 'vision-candidates', itemId: 'cable', candidateIds: ['cable', 'battery', 'unknown'], draftItemId: 'cable' });
    assert.equal(await page.locator('[data-dev-op="correct-item"]').count(), 3);
    await click('correct-item', 'battery');
    // Lost response must recover the durable decision, never resubmit or recapture.
    await page.route('**/vision-review', async route => { await route.fetch(); await route.abort('timedout'); }, { times: 1 });
    await click('apply-correction'); await waitState('REVIEW');
    assert.equal((await active()).vision.decision.item_id, 'battery');
    await page.reload(); await waitState('REVIEW');
    await visual.compare(page, 'review', { name: 'vision-corrected', itemId: 'battery', disableCorrection: true });
    assert.equal(stats().camera.length, 1); assert.equal(stats().primary, 1);
    pass('Candidatos contratados, correção persistida, resposta perdida e refresh sem reclassificação');
    }
    // A decision cannot be changed by a replay, and no economic route is mounted.
    const bad = await fetch(`${origin}/local/simulation/sessions/${event}/vision-review`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Totem-Request': '1' }, body: JSON.stringify({ capture_id: (await active()).vision.capture_id, item_id: 'cable', action: 'confirm' }) });
    assert.equal(bad.status, 409);
    assert.equal((await active()).session.receipt, null);
    assert.equal((await active()).commands.length, 2);
    const storage = await page.evaluate(() => Object.entries(sessionStorage));
    assert.ok(storage.every(([k, v]) => /^[a-f0-9-]{36}$/i.test(v)));
    assert.ok(requests.every(r => !/register|deposit|hatch|confirm-initial/.test(r.path)));
    assert.deepEqual(errors, []);
    assert.equal(visual.results.length, scenario === 'fallback' ? 2 : 5);
    assert.ok(visual.results.every(r => r.passed), 'Strict approved UI regression');
    pass('Sem descarte econômico, alçapão, segredos ou alteração da referência visual');
    await click('discard'); await pin(); await waitState('COMPLETED');
    const completed = await active();
    assert.equal(completed, null, 'Completed session releases only the active slot');
    const saved = await request(`/local/simulation/sessions/${event}`);
    assert.equal(saved.session.state, 'COMPLETED'); assert.equal(saved.session.receipt, null);
    assert.equal(saved.commands.length, 4);
    assert.ok(saved.commands.every(c => c.phase === 'COMPLETED' && c.result === 'SUCCEEDED' && c.source === 'SIMULATED'));
    const completedPosts = requests.filter(r => r.method === 'POST').length;
    await page.reload(); await waitState('COMPLETED');
    assert.equal(requests.filter(r => r.method === 'POST').length, completedPosts);
    assert.equal(stats().camera.length, 1); assert.equal(stats().primary, 1);
    assert.ok(requests.every(r => !/register|deposit/.test(r.path)));
    pass('Item aceito: hatch e retorno simulados no journal, COMPLETED recuperável, sem prêmio');
    }
  } finally {
    if (visual) { visualChecks.push(...visual.results); await visual.close(); }
    if (browser) await browser.close();
    if (server) {
      control({}); fs.writeFileSync(path.join(root, 'stop'), '');
      await Promise.race([closed, pause(4500)]);
      if (!stopped) { server.kill(); await Promise.race([closed, pause(1000)]); }
    }
    fs.writeFileSync(path.join(output, 'vision-session-server.log'), logs);
    if (stopped) fs.rmSync(root, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
    report = { source: 'SYNTHETIC_VISION', scenario, hosted: false, results, visual_checks: visualChecks, errors, requests, temporary_removed: !fs.existsSync(root) };
    fs.writeFileSync(path.join(output, 'vision-session-browser.json'), JSON.stringify(report, null, 2));
    fs.writeFileSync(path.join(output, `vision-session-browser-${scenario}.json`), JSON.stringify(report, null, 2));
    assert.ok(report.temporary_removed, 'Owned fixture cleanup');
    console.log(JSON.stringify({ checks: results.length, visual_checks: visualChecks.length, temporary_removed: report.temporary_removed }));
  }
  return report;
}
(async () => {
  const reports = [];
  const supported = ['recognized', 'rejected', 'failure', 'fallback'];
  const selected = process.argv.slice(2);
  assert.ok(selected.every(scenario => supported.includes(scenario)), 'Unknown vision scenario');
  for (const scenario of selected.length ? selected : supported) reports.push(await main(scenario));
  const report = { source: 'SYNTHETIC_VISION', hosted: false, results: reports.flatMap(r => r.results), visual_checks: reports.flatMap(r => r.visual_checks), errors: reports.flatMap(r => r.errors), requests: reports.flatMap(r => r.requests), temporary_removed: reports.every(r => r.temporary_removed) };
  fs.writeFileSync(path.join(frontend, '.validation/vision-session-browser.json'), JSON.stringify(report, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
