/* Browser on the development host; no browser installed in the image. */
const assert = require('node:assert/strict');
const path = require('node:path');
const repo = path.resolve(__dirname, '../../../..');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || path.join(repo, 'Software/apps/admin_web/node_modules/playwright'));

async function main() {
  const origin = process.env.BINGO_TEST_ORIGIN;
  assert.ok(origin && new URL(origin).hostname === '127.0.0.1');
  const browser = await chromium.launch({
    executablePath: process.env.BROWSER_EXECUTABLE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    headless: true,
  });
  const errors = [], calls = [];
  try {
    const page = await browser.newPage({ viewport: { width: 600, height: 1024 } });
    await page.route('**/*', route => {
      assert.equal(new URL(route.request().url()).origin, origin);
      calls.push(new URL(route.request().url()).pathname);
      return route.continue();
    });
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => { if (response.status() >= 400) errors.push(`${response.status()} ${new URL(response.url()).pathname}`); });
    await page.goto(origin + '/?screen=success', { waitUntil: 'networkidle' });
    await page.locator('[data-operational-state="unavailable"]').waitFor();
    assert.equal(await page.getByText('Iniciar descarte', { exact: true }).count(), 0);
    assert.ok(calls.includes('/local/status'));
    calls.length = 0;
    await page.goto(origin + '/?runtime=demo', { waitUntil: 'networkidle' });
    await page.locator('.demo-notice').waitFor();
    assert.ok((await page.locator('.demo-notice').innerText()).includes('não alteram o saldo real'));
    assert.equal(calls.filter(url => url.startsWith('/local/')).length, 0);
    assert.equal(await page.evaluate(() => [...document.images].filter(img => !img.complete || img.naturalWidth === 0).length), 0);
    await page.evaluate(() => document.fonts.ready);
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ checks: 2, operational: 'blocked', demo: 'isolated', loading_errors: 0 }));
  } finally {
    await browser.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
