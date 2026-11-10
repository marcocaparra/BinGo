/* Real frontend -> HTTP -> FastAPI -> journals -> native C syscall harness.
 * Starts only a disposable container with no device/PWM mounts or credentials. */
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { chromium, launchOptions } = require('./browser_tools.cjs');
const root = path.resolve(__dirname, '../..');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function main() {
  const reservation = http.createServer();
  await new Promise(resolve => reservation.listen(0, '127.0.0.1', resolve));
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  const name = 'bingo-physical-ui-test-' + process.pid;
  const server = spawn('docker', ['run', '--rm', '--name', name, '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--read-only', '--tmpfs', '/tmp:rw,exec,nosuid,nodev,size=256m', '-p', `127.0.0.1:${port}:8000`, '-v', `${root.replaceAll('\\', '/')}:/work:ro`, '-w', '/work/backend', 'bingo-mechanical-ipc:test', 'python', '-B', 'tests/physical_frontend_fixture.py', '--port', '8000'], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let logs = '', browser;
  server.stdout.on('data', chunk => logs += chunk);
  server.stderr.on('data', chunk => logs += chunk);
  const origin = `http://127.0.0.1:${port}`;
  try {
    let ready = false;
    for (let i = 0; i < 600; i++) {
      try { ready = (await (await fetch(origin + '/health')).json()).status === 'ok'; } catch {}
      if (ready) break;
      assert.equal(server.exitCode, null, logs);
      await pause(100);
    }
    assert.ok(ready, logs);
    browser = await chromium.launch(launchOptions);
    const page = await browser.newPage({ viewport: { width: 600, height: 1024 } });
    page.setDefaultTimeout(30000);
    const errors = [], posts = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (request.method() === 'POST') posts.push(new URL(request.url()).pathname); });
    await page.route('**/*', route => {
      assert.equal(new URL(route.request().url()).origin, origin);
      return route.continue();
    });
    const state = value => page.locator(`[data-operational-state="${value}"]`).waitFor();
    const click = (action, value) => page.locator(`[data-op="${action}"]${value ? `[data-value="${value}"]` : ''}`).click();
    await page.goto(origin);
    await state('idle');
    await click('begin'); await click('mode', 'student');
    await click('segment', 'Fundamental II'); await click('grade', '7');
    await click('class', '00000000-0000-4000-8000-000000000010');
    await state('IDENTIFYING'); await click('student', '00000000-0000-4000-8000-000000000011');
    for (const digit of ['0', '0', '1', '2']) await click('pin-key', digit);
    await click('pin-key', 'OK');
    await state('SAFETY'); await click('safe'); await state('INSERTION_READY');
    await click('hand-removed'); await state('REVIEW'); await click('vision-confirm');
    await page.locator('[data-op="hatch"]').waitFor();
    // Two clicks in one event turn: busy guard and durable server ID coalesce.
    await page.locator('[data-op="hatch"]').evaluate(button => { button.click(); button.click(); });
    await state('HATCH_IN_PROGRESS');
    await page.reload();
    await state('INDETERMINATE');
    assert.ok((await page.locator('#kiosk').innerText()).includes('Sequência operacional concluída'));
    assert.equal(posts.filter(value => value.endsWith('/hatch')).length, 1);
    const active = (await (await fetch(origin + '/local/sessions/active')).json()).session;
    const commands = active.operational.commands.filter(c => c.command.operation === 'CYCLE_LOWER_HATCH');
    assert.equal(commands.length, 1);
    assert.equal(commands[0].phase, 'COMPLETED');
    assert.equal(commands[0].source, 'PHYSICAL');
    assert.equal(active.receipt, null);
    await page.reload(); await state('INDETERMINATE');
    assert.equal(await page.locator('.reward-number').count(), 0);
    assert.equal(await page.locator('[data-op="hatch"]').count(), 0);
    assert.deepEqual(errors, []);
    console.log('PASS: frontend -> FastAPI -> MechanicalService -> native C harness; duplicate click, reload, durable operational result, no receipt/reward.');
  } finally {
    if (browser) await browser.close();
    spawnSync('docker', ['stop', '-t', '10', name], { windowsHide: true, stdio: 'ignore' });
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
