const { test } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

const url = process.env.BINGO_TOTEM_URL || 'http://127.0.0.1:8105/apps/totem_ui/';
const browserOptions = {
  headless: true,
  executablePath: process.env.BINGO_BROWSER_PATH || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};

async function enterPin(page, pin) {
  for (const digit of pin) await page.locator(`[data-pin="${digit}"]`).click();
  await page.locator('[data-pin="OK"]').click();
}

test('standard Totem flow reaches a validated result and resets cleanly', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${url}?camera=simulated`);

    await page.getByRole('button', { name: 'Toque para começar' }).click();
    await page.getByRole('button', { name: 'Iniciar descarte' }).click();
    await page.getByRole('button', { name: 'Participar com meu perfil' }).click();
    await page.getByRole('button', { name: 'Fundamental II' }).click();
    await page.getByRole('button', { name: '7º Ano' }).click();
    await page.getByRole('button', { name: '7º Ano A' }).click();
    await page.locator('[data-student="Ana Clara M."]').click();
    await enterPin(page, '1234');
    await enterPin(page, '1234');

    await page.locator('.screen--safety').waitFor();
    await page.locator('[data-safety-safe]').click();
    await page.locator('[data-item-inserted]').waitFor();
    await page.locator('[data-item-inserted]').click();
    await page.locator('[data-hand-confirmed]').click();
    await page.locator('.screen--camera').waitFor();
    await page.locator('.screen--recognized').waitFor();
    await page.locator('[data-recognition-confirm]').click();
    await page.locator('[data-discard-confirm]').click();
    await page.locator('.screen--success').waitFor();

    assert.match(await page.locator('.reward-list').innerText(), /Pontos da turma/);
    assert.match(await page.locator('.reward-list').innerText(), /BinCoins/);
    assert.deepEqual(errors, []);

    await page.getByRole('button', { name: 'Concluir' }).click();
    await page.locator('.screen--sleep').waitFor();
  } finally {
    await browser.close();
  }
});
