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

async function selectStudent(page, name, query = '') {
  await page.goto(`${url}?screen=student&camera=simulated${query}`);
  await page.locator(`[data-student="${name}"]`).click();
}

test('first access creates and confirms a demo PIN without personal contact data', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    await selectStudent(page, 'Ana Clara M.');
    await page.locator('[data-pin-step="create"]').waitFor();
    assert.equal(await page.getByText('Primeiro acesso', { exact: true }).count(), 0);
    assert.equal(await page.getByText(/e-mail|telefone/i).count(), 0);

    await enterPin(page, '1234');
    await page.locator('[data-pin-step="confirm"]').waitFor();
    await enterPin(page, '1235');
    assert.match(await page.locator('.pin-hint').innerText(), /não combinam/i);

    await enterPin(page, '1234');
    await page.locator('.pin-setup-status:not(.is-success)').waitFor();
    assert.match(await page.locator('.pin-setup-status small').innerText(), /Nenhum contato pessoal/i);
    await page.locator('.pin-setup-status.is-success').waitFor();
    await page.locator('.screen--safety').waitFor();
  } finally {
    await browser.close();
  }
});

test('back returns from confirmation to creation and then to student selection', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    await selectStudent(page, 'Ana Clara M.');
    await enterPin(page, '2468');
    await page.locator('[data-pin-step="confirm"]').waitFor();
    await page.locator('[data-back]').click();
    await page.locator('[data-pin-step="create"]').waitFor();
    assert.equal(await page.locator('.pin-dot.filled').count(), 0);
    await page.locator('[data-back]').click();
    await page.locator('.screen--student').waitFor();
  } finally {
    await browser.close();
  }
});

test('an activated demo student keeps the existing PIN login flow', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    await selectStudent(page, 'Marco C.');
    await page.locator('[data-pin-step="login"]').waitFor();
    await enterPin(page, '1234');
    await page.locator('.screen--safety').waitFor();
  } finally {
    await browser.close();
  }
});

test('activation failure offers a controlled retry and then succeeds', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    await selectStudent(page, 'Ana Clara M.', '&scenario=pin-error');
    await enterPin(page, '1357');
    await enterPin(page, '1357');
    await page.locator('[data-pin-step="confirm"] .pin-hint.show').waitFor();
    assert.match(await page.locator('.pin-hint').innerText(), /conexão/i);
    await enterPin(page, '1357');
    await page.locator('.screen--safety').waitFor();
  } finally {
    await browser.close();
  }
});

test('first access remains contained at kiosk sizes and enlarged text', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    for (const viewport of [{ width: 420, height: 720 }, { width: 480, height: 800 }, { width: 600, height: 1024 }]) {
      const page = await browser.newPage({ viewport });
      await selectStudent(page, 'Ana Clara M.');
      await page.evaluate(() => {
        document.querySelectorAll('.guide-bubble, .key, .pin-hint, .cancel-action').forEach(element => {
          element.style.fontSize = `${parseFloat(getComputedStyle(element).fontSize) * 2}px`;
        });
      });
      const layout = await page.evaluate(() => {
        const screen = document.querySelector('.screen');
        const cancel = document.querySelector('.cancel-action').getBoundingClientRect();
        return {
          horizontalOverflow: screen.scrollWidth - screen.clientWidth,
          cancelVisible: cancel.top >= 0 && cancel.bottom <= innerHeight,
        };
      });
      assert.ok(layout.horizontalOverflow <= 1, JSON.stringify({ viewport, layout }));
      assert.equal(layout.cancelVisible, true, JSON.stringify({ viewport, layout }));
      await page.close();
    }
  } finally {
    await browser.close();
  }
});
