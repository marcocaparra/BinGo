/* Uvicorn/SQLite reais em loopback; contratos de UI controlados, sem Supabase/hardware. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawn } = require('node:child_process');
const frontend = path.resolve(__dirname, '..');
const repo = path.resolve(frontend, '../../..');
const backend = path.join(repo, 'Hardware/TotemEdge/backend');
const output = path.join(frontend, '.validation');
fs.mkdirSync(path.join(output, 'tmp'), { recursive: true });
process.env.TMP = process.env.TEMP = path.join(output, 'tmp');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || path.join(repo, 'Software/apps/admin_web/node_modules/playwright'));
const python = process.env.BINGO_TEST_PYTHON || path.join(backend, process.platform === 'win32' ? '.venv/Scripts/python.exe' : '.venv/bin/python');
const executablePath = process.env.BROWSER_EXECUTABLE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const uuid = '00000000-0000-4000-8000-000000000001';
const studentId = '00000000-0000-4000-8000-000000000011';
const classId = '00000000-0000-4000-8000-000000000010';
const sessionBase = { event_id: uuid, class_id: classId, student_id: null, mode: 'student', class_name: '7 A', student_name: null, hand_removed: false, failure_code: null, receipt: null, updated_at: '2026-10-08T12:00:00Z' };

async function main() {
  const reservation = http.createServer();
  await new Promise(resolve => reservation.listen(0, '127.0.0.1', resolve));
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  const origin = `http://127.0.0.1:${port}`;
  const env = { ...process.env, BINGO_SQLITE_PATH: path.join(output, `browser-backend-${process.pid}.sqlite3`) };
  for (const key of ['BINGO_SUPABASE_URL', 'BINGO_MACHINE_ID', 'BINGO_MACHINE_API_KEY', 'BINGO_BACKEND_TIMEOUT_SECONDS']) delete env[key];
  const server = spawn(python, ['-B', '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', String(port)], { cwd: backend, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let logs = '', browser;
  server.stdout.on('data', data => { logs += data; }); server.stderr.on('data', data => { logs += data; });
  const errors = [], results = [], calls = [];
  try {
    let ready = false;
    for (let attempt = 0; attempt < 80; attempt++) {
      try { ready = (await (await fetch(origin + '/health')).json()).status === 'ok'; } catch {}
      if (ready) break;
      if (server.exitCode !== null) throw new Error('Uvicorn encerrou: ' + logs);
      await pause(100);
    }
    assert.ok(ready, logs);
    browser = await chromium.launch({ executablePath, headless: true });
    const context = await browser.newContext({ viewport: { width: 600, height: 1024 } });
    await context.route('**/*', route => {
      assert.equal(new URL(route.request().url()).origin, origin, 'Nenhum destino externo permitido');
      return route.continue();
    });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', msg => { if (msg.type() === 'error' && !msg.text().includes('401') && !msg.text().includes('503')) errors.push(msg.text()); });
    const state = async name => { await page.locator(`[data-operational-state="${name}"]`).waitFor(); };
    const click = async (name, value) => { await page.locator(`button[data-op="${name}"]${value ? `[data-value="${value}"]` : ''}`).click(); };
    await page.goto(origin + '/?screen=success&pin=4', { waitUntil: 'networkidle' });
    await state('unavailable');
    assert.equal(await page.getByText('Iniciar descarte', { exact: true }).count(), 0);
    await click('status'); await state('unavailable');
    assert.equal((await (await fetch(origin + '/local/sessions/active')).json()).session, null);
    await page.screenshot({ path: path.join(output, 'operational-offline.png') });
    results.push('FastAPI/SQLite reais: status seguro, reconsulta e revisão URL ignorada');

    let stored = null;
    let online = true;
    await page.route('**/local/**', async route => {
      const request = route.request(); const pathname = new URL(request.url()).pathname;
      const body = request.postDataJSON(); calls.push({ pathname, body });
      let status = 200, data;
      if (pathname === '/local/status') data = { status: online ? 'ONLINE' : 'OFFLINE', can_start_deposit: online, message: online ? null : 'Indisponível' };
      else if (pathname === '/local/sessions/active') data = { session: stored };
      else if (pathname === '/local/context') data = { classes: [{ id: classId, name: '7 A', segment: 'Fundamental II', grade: '7' }], students: [{ id: studentId, name: 'Aluno', class_id: classId }] };
      else if (pathname === '/local/sessions') { stored = { ...sessionBase, state: 'IDENTIFYING' }; data = stored; }
      else if (pathname.endsWith('/pin')) {
        if (body.pin !== '0012') { status = 401; data = { error: { code: 'STUDENT_PIN_INVALID' } }; }
        else { stored = { ...stored, state: 'SAFETY', student_id: studentId }; data = stored; }
      } else if (pathname.endsWith('/safety')) { stored = { ...stored, state: 'PHYSICAL_BLOCKED' }; data = stored; }
      else if (pathname.endsWith('/retry-registration')) { status = 503; data = { error: { code: 'CENTRAL_TIMEOUT' } }; }
      else if (pathname === '/local/sessions/' + uuid) data = stored;
      else { status = 404; data = { error: { code: 'NOT_FOUND' } }; }
      await route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(data) });
    });
    await page.goto(origin + '/', { waitUntil: 'networkidle' }); await state('idle');
    await click('begin'); await click('mode', 'student'); await click('segment', 'Fundamental II'); await click('grade', '7'); await click('class', classId);
    await state('IDENTIFYING');
    await click('search-toggle'); await click('search-key', 'a'); await click('search-key', 'close');
    await click('student', studentId);
    for (let i = 0; i < 4; i++) await click('pin-key', '9'); await click('pin-key', 'OK');
    await page.getByText('Não foi possível confirmar seu PIN. Tente novamente.').waitFor();
    assert.equal(await page.locator('.pin-dot.filled').count(), 0);
    for (const digit of ['0', '0', '1', '2']) await click('pin-key', digit);
    await click('pin-key', 'OK'); await state('SAFETY');
    await click('safe'); await state('PHYSICAL_BLOCKED');
    await page.clock.install(); await page.clock.fastForward(30000); await state('PHYSICAL_BLOCKED');
    results.push('Contratos locais controlados: escolha por UUID, PIN recusado/correto, triagem bloqueada sem avanço por timer');

    online = false; stored = { ...sessionBase, mode: 'class_only', state: 'REGISTRATION_PENDING' };
    await page.reload({ waitUntil: 'networkidle' }); await state('REGISTRATION_PENDING');
    await click('retry-registration');
    await page.getByText('Não foi possível confirmar a operação. Nenhum sucesso foi presumido.').waitFor();
    await state('REGISTRATION_PENDING');
    const retry = calls.find(c => c.pathname.endsWith('/retry-registration'));
    assert.deepEqual(retry.body, {});
    await page.reload({ waitUntil: 'networkidle' }); await state('REGISTRATION_PENDING');
    results.push('Pending controlado sobrevive ao reload da UI; falha de retry não exibe sucesso nem cria outro evento');

    stored = { ...sessionBase, mode: 'class_only', state: 'REGISTERED', receipt: null };
    await page.reload({ waitUntil: 'networkidle' }); await state('unavailable');
    results.push('REGISTERED sem recibo central é recusado');
    stored.receipt = { id: uuid, event_id: uuid, points_awarded_student: 0, points_awarded_class: 1900, bonus_bincoins_awarded: 0 };
    await page.reload({ waitUntil: 'networkidle' }); await state('REGISTERED');
    assert.ok((await page.locator('#kiosk').innerText()).includes('+1900'));
    results.push('Sucesso controlado somente com recibo vinculado; unidade retornada exibida sem cálculo');
    calls.length = 0;
    await page.goto(origin + '/?runtime=demo&screen=camera', { waitUntil: 'networkidle' });
    await page.getByText('Câmera simulada', { exact: true }).waitFor();
    assert.match(await page.locator('.demo-notice').innerText(), /Modo demonstração ativo/);
    assert.equal(calls.length, 0);
    results.push('Demonstração explicitamente identificada e sem chamadas à API');
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(output, 'operational-browser.json'), JSON.stringify({ browser: await browser.version(), results, errors }, null, 2) + '\n');
    console.log(JSON.stringify({ checks: results.length, errors: errors.length, browser: await browser.version() }));
  } finally {
    if (browser) await browser.close();
    server.kill();
    await Promise.race([new Promise(resolve => server.on('exit', resolve)), pause(5000)]);
    fs.writeFileSync(path.join(output, 'uvicorn-smoke.log'), logs);
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
