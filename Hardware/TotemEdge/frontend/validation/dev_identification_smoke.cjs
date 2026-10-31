/* Official UI -> real local DEV HTTP/SQLite -> existing synthetic broker fixtures. */
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

async function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bingo-dev-ui-'));
  assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
  const control = data => fs.writeFileSync(path.join(root, 'control.json'), JSON.stringify(data));
  control({});
  const reserve = http.createServer();
  await new Promise(resolve => reserve.listen(0, '127.0.0.1', resolve));
  const port = reserve.address().port;
  await new Promise(resolve => reserve.close(resolve));
  const origin = `http://127.0.0.1:${port}`;
  const env = { ...process.env };
  for (const key of Object.keys(env)) if (/^(BINGO_|SUPABASE_|AWS_|GEMINI_|GOOGLE_)/i.test(key) || /^(https?_proxy|all_proxy|no_proxy)$/i.test(key)) delete env[key];
  let server, closed, hasClosed = false, logs = '', browser, visual;
  const visualResults = [];
  const results = [], requests = [], errors = [];
  const pass = label => { results.push(label); console.log('PASS: ' + label); };
  const output = path.join(frontend, '.validation');
  fs.mkdirSync(output, { recursive: true });
  async function start() {
    fs.rmSync(path.join(root, 'stop'), { force: true });
    hasClosed = false;
    server = spawn(python, ['-B', 'tests/dev_frontend_fixture.py', '--root', root, '--port', String(port)], { cwd: backend, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    closed = new Promise(resolve => server.once('close', () => { hasClosed = true; resolve(); }));
    server.stdout.on('data', b => { logs += b; }); server.stderr.on('data', b => { logs += b; });
    server.on('error', () => errors.push('Fixture process could not start'));
    let ready = false, lastProbe = null;
    for (let i = 0; i < 80; i++) {
      try { const r = await fetch(origin + '/health', { headers: { Connection: 'close' }, cache: 'no-store' }); const body = await r.json(); lastProbe = { status: r.status, runtime: r.headers.get('X-Totem-Runtime'), live: body.status }; ready = r.status === 200 && lastProbe.runtime === 'dev-integration' && body.status === 'ok'; } catch (e) { lastProbe = { error: e.cause?.code || e.name }; }
      if (ready) break;
      if (hasClosed) throw new Error('Synthetic DEV fixture stopped');
      await pause(100);
    }
    assert.ok(ready, 'Synthetic DEV HTTP startup: ' + JSON.stringify(lastProbe));
  }
  async function stop() {
    if (!server) return;
    fs.writeFileSync(path.join(root, 'stop'), '');
    await Promise.race([closed, pause(4500)]);
    if (!hasClosed) server.kill();
    await Promise.race([closed, pause(500)]);
    assert.ok(hasClosed, 'Fixture must close before cleanup/restart');
    server = null;
  }
  async function request(route, body, status = 200) {
    const r = await fetch(origin + route, { method: body === undefined ? 'GET' : 'POST', headers: { 'Content-Type': 'application/json', 'X-Totem-Request': '1', Origin: origin }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    assert.equal(r.status, status, 'Controlled HTTP status');
    return r.json();
  }
  const active = async () => (await request('/local/simulation/sessions/active')).snapshot;
  try {
    await start();
    const ids = JSON.parse(fs.readFileSync(path.join(root, 'public.json'), 'utf8'));
    let context, page;
    async function openBrowser() {
      // Deterministic compositor stages, not a CSS override or pixel tolerance.
      // Chromium reference: headless/lib/browser/command_line_handler.cc.
      browser = await chromium.launch({ ...launchOptions, args: [...(launchOptions.args || []), '--disable-gpu', '--force-color-profile=srgb', '--force-device-scale-factor=1', '--run-all-compositor-stages-before-draw', '--disable-threaded-animation', '--disable-partial-raster'] });
      context = await browser.newContext({ viewport: { width: 600, height: 1024 }, deviceScaleFactor: 1 });
      await context.route('**/*', route => {
        assert.equal(new URL(route.request().url()).origin, origin, 'Only owned loopback fixture allowed');
        return route.continue();
      });
      page = await context.newPage();
      await page.clock.install({ time });
      await page.clock.pauseAt(new Date(time.getTime() + 60000));
      page.on('pageerror', () => errors.push('Browser runtime error'));
      page.on('request', r => {
        const u = new URL(r.url());
        requests.push({ method: r.method(), path: u.pathname });
        assert.equal(u.searchParams.has('pin'), false);
        assert.equal(r.headers()['x-api-key'], undefined);
        assert.equal(r.headers()['authorization'], undefined);
      });
    }
    await openBrowser();
    const stage = name => page.locator(`[data-dev-stage="${name}"]`).waitFor();
    const state = name => page.locator(`[data-operational-state="${name}"]`).waitFor();
    const click = (op, value) => page.locator(`${op === 'search-toggle' ? '[data-search-toggle]' : 'button'}[data-dev-op="${op}"]${value ? `[data-value="${value}"]` : ''}`).click();
    async function begin(compare = false, gradeLabel = '7º Ano') {
      await page.locator('button[data-dev-op="wake"],button[data-dev-op="begin"]').first().waitFor();
      if (await page.locator('button[data-dev-op="wake"]').count()) await click('wake');
      if (compare) await visual.compare(page, 'idle');
      await click('begin'); await stage('identity');
      if (compare) await visual.compare(page, 'identity');
      await click('mode', 'student');
      if (await page.locator('[data-dev-stage="segment"]').count()) {
        if (compare) await visual.compare(page, 'segment');
        await click('segment', 'Fundamental II'); await stage('year');
        if (compare) await visual.compare(page, 'year');
        await click('grade', gradeLabel);
      }
      await stage('classes');
      if (compare) await visual.compare(page, 'class');
    }
    async function choose() { await click('class', ids.class_id); await stage('students'); await click('student', ids.student_id); await stage('pin'); }
    async function enter(value) { for (const digit of value) await click('pin', digit); }
    async function fresh() {
      const current = await active();
      if (current) await request(`/local/simulation/sessions/${current.session.event_id}/cancel`, {});
      await page.evaluate(() => sessionStorage.clear());
      control({});
      await page.goto(origin); await stage('idle'); await begin(); await choose();
      return (await active()).session.event_id;
    }
    async function authenticated() {
      const event = await fresh();
      await enter('0012'); await click('pin', 'OK'); await state('SAFETY');
      return event;
    }
    const visualData = await request('/local/dev/context');
    visual = await openApprovedVisual(context, output, visualData);
    await page.goto(origin); await stage('idle');
    await visual.compare(page, 'sleep');
    await begin(true);
    await page.evaluate(id => { const selector = `[data-dev-op="class"][data-value="${id}"]`; document.querySelector(selector).click(); document.querySelector(selector)?.click(); }, ids.class_id);
    await stage('students');
    await visual.compare(page, 'student');
    await click('search-toggle');
    await visual.compare(page, 'student', { name: 'student-search', searchActive: true });
    await click('search-toggle');
    assert.equal(await page.locator('.visual-keyboard').count(), 1, 'Clicking the original search field keeps its keyboard open');
    const postsBeforeSearch = requests.filter(r => r.method === 'POST').length;
    await click('search-key', 'z');
    assert.equal(await page.locator('button[data-dev-op="student"]').count(), 0);
    await click('search-key', 'clear');
    assert.equal(await page.locator('.is-keyboard-closing .visual-keyboard').count(), 1);
    await page.clock.runFor(260);
    assert.equal(await page.locator('.visual-keyboard').count(), 0);
    assert.equal(await page.locator('button[data-dev-op="student"]').count(), visualData.students.length);
    assert.equal(requests.filter(r => r.method === 'POST').length, postsBeforeSearch);
    pass('Busca e teclado originais filtram contexto sem criar ou autenticar outra sessão');
    await click('student', ids.student_id); await stage('pin');
    await visual.compare(page, 'pin');
    await page.screenshot({ path: path.join(output, 'dev-identification-pin.png') });
    const first = (await active()).session.event_id;
    assert.equal((await active()).session.state, 'IDENTIFYING');
    pass('Contexto real HTTP do broker sintético; turma/aluno e sessão IDENTIFYING');
    await enter('12');
    assert.ok(await page.locator('[data-dev-op="pin"][data-value="OK"]').isDisabled());
    await request(`/local/dev/sessions/${first}/identity`, { ...ids, other_id: undefined, pin: '12' }, 422);
    pass('PIN incompleto bloqueado na UI e contrato HTTP inválido recusado');
    await page.reload(); await stage('classes'); await choose();
    assert.equal((await active()).session.event_id, first);
    assert.equal(requests.filter(r => r.method === 'POST' && r.path === '/local/simulation/sessions').length, 1);
    pass('Refresh IDENTIFYING recupera event_id, sem outra criação');
    await enter('9999'); await click('pin', 'OK');
    await page.getByRole('alert').filter({ hasText: 'PIN não confirmado' }).waitFor();
    await visual.compare(page, 'pin', { name: 'pin-error', warning: 'PIN não confirmado. Tente novamente.' });
    assert.equal((await active()).identity, null);
    assert.equal(await page.locator('.pin-dot.filled').count(), 0);
    pass('PIN incorreto: 401, vínculo ausente e PIN transitório limpo');
    control({ slow_pin: true }); await enter('0012');
    const beforePosts = requests.filter(r => r.path.endsWith('/identity')).length;
    await page.evaluate(() => { const b = document.querySelector('[data-dev-op="pin"][data-value="OK"]'); b.click(); document.querySelector('[data-dev-op="pin"][data-value="OK"]')?.click(); });
    await state('SAFETY');
    await visual.compare(page, 'safety');
    visualResults.push(...visual.results);
    await visual.close(); visual = null;
    let bound = await active();
    assert.equal(bound.identity.student_id, ids.student_id);
    assert.equal(requests.filter(r => r.path.endsWith('/identity')).length - beforePosts, 1);
    pass('PIN correto e clique duplo: uma submissão, SAFETY validado pelo backend');
    await page.screenshot({ path: path.join(output, 'dev-identification-safety.png') });
    const stamp = bound.identity.validated_at;
    const calls = () => JSON.parse(fs.readFileSync(path.join(root, 'stats.json'), 'utf8')).calls;
    control({ offline: true }); const beforeCalls = calls().length;
    await page.reload(); await state('SAFETY');
    assert.equal((await active()).identity.validated_at, stamp);
    assert.equal(calls().length, beforeCalls);
    pass('Refresh SAFETY offline restaura vínculo sem PIN nem consulta central');
    // Restart sequentially, just like the initial startup. Keep the browser from
    // contending with Python's cold imports, without changing any deadline.
    await browser.close(); browser = null;
    await stop(); await start(); await openBrowser();
    await page.goto(origin); await state('SAFETY');
    assert.equal((await active()).session.event_id, first);
    assert.equal(calls().length, 0);
    pass('Reinício do backend conserva SQLite e identidade, com central indisponível');
    await click('back'); await state('CANCELLED'); await page.reload(); await state('CANCELLED');
    await click('new');
    await page.getByRole('alert').filter({ hasText: 'central DEV está indisponível' }).waitFor();
    pass('Terminal recuperado por ID; nova autenticação bloqueada offline');
    control({ empty: true }); await click('refresh'); await stage('idle'); await begin();
    assert.ok((await page.locator('#kiosk').innerText()).includes('Nenhuma turma disponível'));
    pass('Contexto vazio sem fallback para dados inventados');
    const event = await fresh(); control({ offline: true }); await enter('0012'); await click('pin', 'OK');
    await page.getByRole('alert').filter({ hasText: 'central DEV está indisponível' }).waitFor();
    assert.equal((await active()).identity, null); assert.equal((await active()).session.event_id, event);
    pass('503 preserva sessão não autenticada e bloqueia nova submissão');
    control({}); await click('refresh'); await stage('pin');
    await page.route('**/local/dev/sessions/*/identity', async route => { const response = await route.fetch(); assert.equal(response.status(), 200); await route.abort('timedout'); }, { times: 1 });
    await enter('0012'); await click('pin', 'OK'); await state('SAFETY');
    assert.equal((await active()).session.event_id, event);
    assert.ok((await page.getByRole('alert').innerText()).includes('resposta'));
    pass('Resposta perdida/timeout de transporte após commit recupera SAFETY por GET');
    const inconsistent = await fresh();
    await page.route('**/local/dev/sessions/*/identity', route => route.fulfill({ status: 200, contentType: 'application/json', body: '{}' }), { times: 1 });
    await enter('0012'); await click('pin', 'OK');
    await page.getByRole('alert').filter({ hasText: 'inconsistente' }).waitFor();
    assert.equal((await active()).identity, null); assert.equal((await active()).session.event_id, inconsistent);
    pass('Resposta HTTP inesperada não fabrica autenticação nem SAFETY');
    await request(`/local/simulation/sessions/${inconsistent}/cancel`, {});
    await page.evaluate(() => sessionStorage.clear());
    await page.goto(origin); await stage('idle'); await begin();
    const attempts = [];
    const watchStart = r => { if (r.method() === 'POST' && new URL(r.url()).pathname === '/local/simulation/sessions') attempts.push(r.postDataJSON().command_id); };
    page.on('request', watchStart);
    await page.route('**/local/simulation/sessions', route => route.abort('failed'), { times: 1 });
    await click('class', ids.class_id);
    await page.locator('.status-panel > strong').filter({ hasText: 'Resposta não confirmada' }).waitFor();
    await page.reload(); await stage('idle'); await click('resume'); await stage('classes'); await choose();
    assert.equal(attempts.length, 2); assert.equal(attempts[0], attempts[1]);
    page.removeListener('request', watchStart);
    pass('Início sem resposta e refresh preservam command_id; retry cria uma única sessão');
    const conflict = await fresh();
    const other = await request(`/local/dev/sessions/${conflict}/identity`, { class_id: ids.class_id, student_id: ids.other_id, pin: '0012' });
    await enter('0012'); await click('pin', 'OK'); await state('SAFETY');
    await page.getByRole('alert').filter({ hasText: 'conflito' }).waitFor();
    assert.ok((await page.locator('#kiosk').innerText()).includes('Outro aluno sintético'));
    assert.equal((await active()).identity.validated_at, other.identity.validated_at);
    pass('409 não troca identidade: mostra conflito e vínculo durável vencedor');
    await request(`/local/simulation/sessions/${conflict}/safety`, { has_risk: false });
    await page.reload(); await state('PHYSICAL_BLOCKED');
    assert.ok((await page.locator('#kiosk').innerText()).includes('Sessão já avançou'));
    assert.equal((await active()).commands.length, 0);
    assert.equal((await active()).session.receipt, null);
    pass('Etapa avançada somente leitura, sem regressão de estado ou movimento');
    await request(`/local/simulation/sessions/${conflict}/cancel`, {});

    const safeEvent = await authenticated();
    const safetyPosts = () => requests.filter(r => r.method === 'POST' && r.path.endsWith('/safety')).length;
    const beforeSafe = safetyPosts();
    let releaseSafety;
    const heldSafety = new Promise(resolve => { releaseSafety = resolve; });
    await page.route(`**/local/simulation/sessions/${safeEvent}/safety`, async route => {
      assert.deepEqual(route.request().postDataJSON(), { has_risk: false });
      await heldSafety; await route.continue();
    }, { times: 1 });
    try {
      await page.evaluate(() => {
        document.querySelector('[data-safety-safe]').click();
        document.querySelector('[data-safety-safe]')?.click();
        document.querySelector('[data-safety-risk]')?.click();
      });
      assert.equal(await page.locator('[data-safety-safe]').isDisabled(), true);
      assert.equal(await page.locator('[data-safety-risk]').isDisabled(), true);
      assert.equal((await active()).session.state, 'SAFETY');
    } finally { releaseSafety(); }
    await state('PHYSICAL_BLOCKED');
    let checkpoint = await active();
    assert.equal(safetyPosts() - beforeSafe, 1);
    assert.equal(checkpoint.session.event_id, safeEvent);
    assert.deepEqual(checkpoint.commands, []); assert.equal(checkpoint.session.receipt, null);
    assert.equal(await page.locator('[data-dev-op="open"]').count(), 0);
    await page.reload(); await state('PHYSICAL_BLOCKED');
    assert.equal((await active()).session.event_id, safeEvent);
    pass('Sim, está seguro: false real HTTP, uma submissão com cliques duplicados/opostos, PHYSICAL_BLOCKED recuperado sem movimento');

    const riskEvent = await authenticated();
    await page.route(`**/local/simulation/sessions/${riskEvent}/safety`, route => {
      assert.deepEqual(route.request().postDataJSON(), { has_risk: true });
      return route.continue();
    }, { times: 1 });
    const beforeRisk = safetyPosts();
    await page.evaluate(() => {
      document.querySelector('[data-safety-risk]').click();
      document.querySelector('[data-safety-risk]')?.click();
      document.querySelector('[data-safety-safe]')?.click();
    });
    await state('CANCELLED');
    assert.equal(safetyPosts() - beforeRisk, 1);
    checkpoint = await request(`/local/simulation/sessions/${riskEvent}`);
    assert.equal(checkpoint.session.failure_code, 'SAFETY_RISK');
    assert.equal(await active(), null); assert.deepEqual(checkpoint.commands, []);
    assert.equal(checkpoint.session.receipt, null);
    assert.ok((await page.locator('.teacher-card').innerText()).includes('Não force a abertura nem toque no item.'));
    visual = await openApprovedVisual(context, output, visualData);
    await visual.compare(page, 'teacher');
    visualResults.push(...visual.results); await visual.close(); visual = null;
    await page.reload(); await state('CANCELLED');
    assert.ok((await page.locator('.guide-bubble').innerText()).includes('Procure um responsável antes de continuar.'));
    const startsBeforeAck = requests.filter(r => r.method === 'POST' && r.path === '/local/simulation/sessions').length;
    await click('new', 'idle'); await stage('idle');
    assert.equal(requests.filter(r => r.method === 'POST' && r.path === '/local/simulation/sessions').length, startsBeforeAck);
    pass('Encontrei um risco: true cancela no backend; orientação original recuperada após refresh; Entendi volta ao início');

    const failedSafety = await authenticated();
    await page.route(`**/local/simulation/sessions/${failedSafety}/safety`, route => route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: { code: 'CONTROLLED_UNAVAILABLE' } }) }), { times: 1 });
    await click('safety', 'safe');
    await page.getByRole('alert').filter({ hasText: 'indisponível' }).waitFor();
    assert.equal((await active()).session.state, 'SAFETY');
    assert.equal((await active()).session.event_id, failedSafety);
    pass('HTTP 503 na segurança não confirma decisão nem muda o snapshot SAFETY');

    const unchangedSafety = await active();
    await page.route(`**/local/simulation/sessions/${failedSafety}/safety`, route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(unchangedSafety) }), { times: 1 });
    await click('safety', 'risk');
    await page.getByRole('alert').filter({ hasText: 'inconsistente' }).waitFor();
    assert.equal((await active()).session.state, 'SAFETY');
    assert.equal(await page.locator('.teacher-card').count(), 0);
    pass('Resposta 200 inconsistente da segurança não fabrica cancelamento ou avanço');

    await page.route(`**/local/simulation/sessions/${failedSafety}/safety`, async route => { const response = await route.fetch(); assert.equal(response.status(), 200); await route.abort('timedout'); }, { times: 1 });
    const beforeLostSafe = safetyPosts();
    await click('safety', 'safe'); await state('PHYSICAL_BLOCKED');
    assert.ok((await page.getByRole('alert').innerText()).includes('resposta'));
    assert.equal(safetyPosts() - beforeLostSafe, 1);
    assert.equal((await active()).session.event_id, failedSafety);
    assert.deepEqual((await active()).commands, []);
    pass('Resposta perdida após segurança false recupera PHYSICAL_BLOCKED por GET, sem retry automático');

    const lostRisk = await authenticated();
    await page.route(`**/local/simulation/sessions/${lostRisk}/safety`, async route => { const response = await route.fetch(); assert.equal(response.status(), 200); await route.abort('timedout'); }, { times: 1 });
    const beforeLostRisk = safetyPosts();
    await click('safety', 'risk'); await state('CANCELLED');
    assert.equal(safetyPosts() - beforeLostRisk, 1); assert.equal(await active(), null);
    assert.ok((await page.locator('.teacher-card').innerText()).includes('Não force a abertura'));
    await page.reload(); await state('CANCELLED');
    assert.ok((await page.locator('.guide-bubble').innerText()).includes('Procure um responsável'));
    pass('Resposta perdida após segurança true recupera cancelamento e orientação duráveis pelo mesmo event_id');

    const concurrentSafety = await authenticated();
    await page.route(`**/local/simulation/sessions/${concurrentSafety}/safety`, async route => {
      await request(`/local/simulation/sessions/${concurrentSafety}/safety`, { has_risk: true });
      await route.continue();
    }, { times: 1 });
    await click('safety', 'safe'); await state('CANCELLED');
    await page.getByRole('alert').filter({ hasText: 'conflito' }).waitFor();
    assert.equal((await request(`/local/simulation/sessions/${concurrentSafety}`)).session.failure_code, 'SAFETY_RISK');
    assert.deepEqual((await request(`/local/simulation/sessions/${concurrentSafety}`)).commands, []);
    pass('HTTP 409 por decisão concorrente respeita cancelamento vencedor sem afirmar decisão segura');

    const guardedSafety = await authenticated();
    await page.route('**/local/simulation/sessions/active', async route => {
      const response = await route.fetch(), body = await response.json();
      body.snapshot.allowed_actions = ['cancel'];
      await route.fulfill({ response, json: body });
    }, { times: 1 });
    await page.reload(); await state('SAFETY');
    assert.equal(await page.locator('[data-safety-safe]').isDisabled(), true);
    assert.equal(await page.locator('[data-safety-risk]').isDisabled(), true);
    const beforeGuarded = safetyPosts();
    await page.evaluate(() => { const button = document.querySelector('[data-safety-safe]'); button.disabled = false; button.click(); });
    await page.waitForFunction(() => document.querySelector('[data-safety-safe]')?.disabled === false);
    assert.equal(safetyPosts(), beforeGuarded);
    assert.equal((await active()).session.state, 'SAFETY');
    await request(`/local/simulation/sessions/${guardedSafety}/cancel`, {});
    pass('Sem safety em allowed_actions, controles e handler bloqueiam POST e apenas recuperam snapshot');

    const pinCancelled = await fresh();
    await click('cancel'); await state('CANCELLED'); await page.reload(); await state('CANCELLED');
    const cancelledSnapshot = await request(`/local/simulation/sessions/${pinCancelled}`);
    assert.equal(cancelledSnapshot.identity, null);
    assert.equal(cancelledSnapshot.session.state, 'CANCELLED');
    assert.equal(cancelledSnapshot.commands.length, 0);
    pass('Cancelar descarte original no PIN encerra a preparação e preserva terminal após refresh');
    await page.evaluate(() => sessionStorage.clear());
    control({ unsafe_labels: true });
    await page.goto(origin); await stage('idle');
    await begin(false, '</span></button></div><img src=/label-test>');
    assert.ok((await page.locator('#kiosk').innerText()).includes('<Turma sintética>'));
    await click('class', ids.class_id); await stage('students');
    assert.ok((await page.locator('#kiosk').innerText()).includes('<Aluno sintético>'));
    assert.equal(await page.locator('#kiosk img[src="/label-test"]').count(), 0);
    assert.ok(requests.every(r => r.path !== '/label-test'));
    await click('student', ids.student_id); await click('cancel'); await state('CANCELLED');
    pass('Rótulos do contexto são texto literal: turma, aluno e ano não injetam elementos ou requests');
    control({});
    await page.evaluate(() => sessionStorage.clear());
    await page.goto(origin); await stage('idle'); await begin();
    const beforeStorageFailure = requests.filter(r => r.method === 'POST').length;
    await page.evaluate(() => { Storage.prototype.setItem = () => { throw new DOMException('Storage blocked', 'SecurityError'); }; });
    await click('class', ids.class_id);
    await page.getByRole('alert').filter({ hasText: 'preservar o identificador' }).waitFor();
    await click('refresh'); await stage('idle'); await click('resume');
    await page.getByRole('alert').filter({ hasText: 'preservar o identificador' }).waitFor();
    assert.equal(requests.filter(r => r.method === 'POST').length, beforeStorageFailure);
    assert.equal(await active(), null);
    pass('Armazenamento de IDs indisponível bloqueia criação e retry antes do POST');
    const stored = await page.evaluate(() => ({ session: Object.entries(sessionStorage), local: Object.entries(localStorage), cookie: document.cookie }));
    assert.ok(stored.session.every(([key, value]) => ['bingo.dev.event', 'bingo.dev.command'].includes(key) && /^[a-f0-9-]{36}$/i.test(value)));
    assert.deepEqual(stored.local, []); assert.equal(stored.cookie, '');
    assert.deepEqual(await context.cookies(), []);
    assert.ok(requests.filter(r => r.method === 'POST').every(r => r.path === '/local/simulation/sessions' || /^\/local\/dev\/sessions\/[^/]+\/identity$/.test(r.path) || /^\/local\/simulation\/sessions\/[^/]+\/(cancel|safety)$/.test(r.path)));
    assert.ok(calls().every(c => ['/functions/v1/health-v1', '/functions/v1/totem-context-v1', '/functions/v1/totem-student-pin-v1'].includes(c.path)));
    assert.deepEqual(errors, []);
    pass('Sem PIN/segredos em armazenamento, cookies, URLs ou logs de teste; sem chamadas mecânicas/econômicas');
    assert.equal(visualResults.length, 12, 'Every approved identification and risk orientation screen must be compared');
    assert.deepEqual(visualResults.filter(result => !result.passed).map(result => result.screen), [], 'Approved UI comparison failed; inspect unmasked pairs and strict design contracts');
  } finally {
    try { if (visual) { visualResults.push(...visual.results); await visual.close(); } if (browser) await browser.close(); }
    finally {
      await stop();
      fs.writeFileSync(path.join(output, 'dev-identification-server.log'), logs);
      let cleanupError;
      try { fs.rmSync(root, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 }); }
      catch (error) { cleanupError = error; }
      const report = { source: 'SYNTHETIC_DEV', hosted: false, visual_reference: { revision: 'a9310a6eba3a979cc1349319d64656c0c7898064', path: 'Software/apps/totem_ui', viewport: '600x1024', masks: [] }, visual_checks: visualResults, results, errors, temporary_removed: !fs.existsSync(root), requests };
      fs.writeFileSync(path.join(output, 'dev-identification-browser.json'), JSON.stringify(report, null, 2));
      console.log(JSON.stringify({ checks: results.length, visual_checks: visualResults.length, errors: errors.length, temporary_removed: report.temporary_removed }));
      if (cleanupError) throw new Error('Owned synthetic fixture cleanup failed; inspect report and exact temporary root: ' + root, { cause: cleanupError });
    }
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
