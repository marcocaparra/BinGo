/* Smoke do protótipo: somente servidores estáticos em loopback, sem integrações. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { createHash } = require('node:crypto');

const frontend = path.resolve(__dirname, '..');
const repo = path.resolve(frontend, '../../..');
const output = path.join(frontend, '.validation');
fs.mkdirSync(path.join(output, 'tmp'), { recursive: true });
process.env.TEMP = process.env.TMP = path.join(output, 'tmp');
// Usa uma instalação de ferramentas já disponível; não adiciona dependência ao produto.
const { chromium, launchOptions } = require('./browser_tools.cjs');
const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.png': 'image/png', '.ttf': 'font/ttf' };

async function serve(root) {
  const server = http.createServer((req, res) => {
    try {
      assert.equal(req.method, 'GET');
      const relative = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
      let file = path.resolve(root, '.' + relative);
      assert.ok(file === root || file.startsWith(root + path.sep));
      if (fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
      res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    } catch {
      res.writeHead(404); res.end();
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return { server, url: `http://127.0.0.1:${server.address().port}` };
}

async function main() {
  const original = await serve(path.join(repo, 'Software'));
  const copy = await serve(frontend);
  let browser;
  const problems = [];
  const comparisons = [];
  const flows = [];
  let requests = 0;
  try {
    browser = await chromium.launch(launchOptions);
    const contexts = [];
    for (const target of [original, copy]) {
      const context = await browser.newContext({ viewport: { width: 600, height: 1024 } });
      await context.route('**/*', route => {
        const url = new URL(route.request().url());
        if (url.origin !== target.url) {
          problems.push(`Destino não autorizado: ${url.origin}`);
          return route.abort();
        }
        requests += 1;
        return route.continue();
      });
      const page = await context.newPage();
      page.on('pageerror', error => problems.push(error.message));
      page.on('console', msg => { if (msg.type() === 'error') problems.push(msg.text()); });
      page.on('requestfailed', req => problems.push(`Falha HTTP: ${req.url()}`));
      page.on('response', response => {
        if (response.status() >= 400) problems.push(`HTTP ${response.status()}: ${response.url()}`);
      });
      const time = new Date('2026-10-08T12:00:00Z');
      // Install before the pause target: install starts a progressing clock.
      await page.clock.install({ time: new Date(time.getTime() - 60_000) });
      await page.clock.pauseAt(time);
      contexts.push({ context, page, base: target.url + (target === original ? '/apps/totem_ui/' : '/') });
    }
    const code = fs.readFileSync(path.join(frontend, 'script.js'), 'utf8');
    const screens = [...code.slice(code.indexOf('const screens'), code.indexOf('let currentIndex'))
      .matchAll(/id: "([\w-]+)"/g)].map(match => match[1]);
    assert.equal(screens.length, 29);
    for (const screen of screens) {
      const results = [];
      for (const [index, target] of contexts.entries()) {
        await target.page.goto(target.base + '?screen=' + screen + (index ? '&runtime=demo' : ''), { waitUntil: 'networkidle' });
        if (index) {
          assert.match(await target.page.locator('.demo-notice').innerText(), /Modo demonstração ativo/);
          await target.page.locator('.demo-notice').evaluate(el => el.remove());
        }
        await target.page.evaluate(() => document.fonts.ready);
        const result = await target.page.evaluate(() => ({
          html: document.querySelector('#kiosk').innerHTML,
          missingImages: [...document.images].filter(img => !img.complete || !img.naturalWidth).map(img => img.src),
          bodyText: document.body.innerText,
          fontErrors: [...document.fonts].filter(font => font.status === 'error').map(font => font.family),
        }));
        assert.deepEqual(result.missingImages, [], screen);
        assert.deepEqual(result.fontErrors, [], screen);
        if (['sleep', 'camera', 'success'].includes(screen)) {
          const image = await target.page.screenshot({ path: path.join(output, `${index ? 'copy' : 'original'}-${screen}.png`), animations: 'disabled' });
          result.imageHash = createHash('sha256').update(image).digest('hex');
        }
        results.push(result);
      }
      assert.deepEqual(results[0], results[1], `Original/cópia: ${screen}`);
      comparisons.push({ screen, domEqual: true, ...(results[0].imageHash ? { screenshotEqual: true } : {}) });
    }

    const { page, base } = contexts[1];
    async function screenIs(id) {
      assert.equal(await page.evaluate(() => screens[currentIndex].id), id);
    }
    async function start(scenario = 'success') {
      await page.goto(base + '?runtime=demo&scenario=' + scenario, { waitUntil: 'networkidle' });
      await page.locator('button[data-next="idle"]').click();
      await page.locator('[data-start-session]').click();
    }
    async function identify() {
      await page.locator('[data-mode="student"]').click();
      await page.locator('[data-segment]').first().click();
      await page.locator('[data-year]').first().click();
      await page.locator('[data-class]').first().click();
      await page.locator('[data-student]').first().click();
      for (let digit = 0; digit < 4; digit++) await page.locator('[data-pin="1"]').click();
      await page.locator('[data-pin="OK"]').click();
      await screenIs('safety');
    }
    async function analyze() {
      await page.locator('[data-safety-safe]').click();
      await screenIs('opening');
      await page.clock.runFor(2200);
      await screenIs('insert');
      await page.locator('[data-item-inserted]').click();
      await page.locator('[data-hand-confirmed]').click();
      await page.clock.runFor(3200);
      await screenIs('camera');
      assert.equal(await page.locator('video, canvas').count(), 0);
      await page.clock.runFor(2800);
      await screenIs('classification');
      await page.clock.runFor(2400);
    }
    await start(); await identify(); await analyze(); await screenIs('recognized');
    await page.locator('[data-recognition-confirm]').click();
    await page.locator('[data-discard-confirm]').click();
    await page.clock.runFor(4500); await screenIs('success');
    await page.clock.runFor(6000); await screenIs('sleep');
    flows.push('Identificação/PIN demonstrativo, ciclo por timers, sucesso e reset');

    await start('unavailable'); await screenIs('unavailable');
    flows.push('Indisponibilidade demonstrativa bloqueia a navegação inicial');
    await start('uncertain'); await identify(); await analyze(); await screenIs('secondary-analysis');
    await page.clock.runFor(2600); await screenIs('recognized');
    await page.locator('[data-correction-open]').click();
    await page.locator('[data-correct-item="unknown"]').click();
    await page.locator('[data-apply-correction]').click(); await screenIs('review');
    assert.equal(await page.evaluate(() => classificationOrigin), 'UNIDENTIFIED');
    flows.push('Análise secundária e correção para UNKNOWN simuladas');
    await start('rejected'); await identify(); await analyze(); await screenIs('rejected');
    await page.locator('[data-return-start]').click();
    await page.clock.runFor(2200); await screenIs('return-confirm');
    await page.locator('[data-return-confirm]').click(); await screenIs('sleep');
    flows.push('Recusa e devolução simuladas');
    await start('connection-before'); await identify(); await analyze();
    await page.locator('[data-recognition-confirm]').click();
    await page.locator('[data-discard-confirm]').click(); await screenIs('connection-interrupted');
    flows.push('Falha demonstrativa antes da queda');
    await start('connection-after'); await identify(); await analyze();
    await page.locator('[data-recognition-confirm]').click();
    await page.locator('[data-discard-confirm]').click();
    await page.clock.runFor(4500); await screenIs('post-drop-recovery');
    await page.reload({ waitUntil: 'networkidle' }); await screenIs('sleep');
    assert.equal(await page.evaluate(() => registrationStatus), 'idle');
    flows.push('Reload perde a pendência demonstrativa: risco confirmado');
    await page.goto(base + '?runtime=demo&screen=post-drop-recovery', { waitUntil: 'networkidle' });
    await page.locator('[data-restore-connection]').click(); await screenIs('success');
    flows.push('Recuperação visual declara sucesso sem resposta remota');
    await start('mechanical'); await identify();
    await page.locator('[data-safety-safe]').click();
    await page.clock.runFor(2200); await screenIs('mechanical-error');
    flows.push('Falha mecânica demonstrativa');
    await start(); await identify(); await page.locator('[data-safety-risk]').click(); await screenIs('teacher');
    flows.push('Triagem de risco interrompe o fluxo visual');
    await start(); await page.locator('[data-mode="classOnly"]').click();
    await page.locator('[data-segment]').first().click();
    await page.locator('[data-year]').first().click();
    await page.locator('[data-class]').first().click(); await screenIs('safety');
    flows.push('Modo somente turma pula aluno e PIN');
    assert.deepEqual(problems, []);
    const report = { browser: await browser.version(), viewport: '600x1024',
      screens: comparisons, simulatedFlows: flows, httpRequests: requests, errors: problems };
    fs.writeFileSync(path.join(output, 'browser.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({ browser: report.browser, screens: comparisons.length,
      identicalScreenshots: comparisons.filter(x => x.screenshotEqual).length, simulatedFlows: flows.length,
      httpRequests: requests, errors: problems.length }));
  } finally {
    if (browser) await browser.close();
    await Promise.all([original.server, copy.server].map(server => new Promise(resolve => server.close(resolve))));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
