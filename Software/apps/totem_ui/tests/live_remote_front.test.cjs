const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');

const url = process.env.BINGO_TOTEM_URL || 'http://127.0.0.1:8107/apps/totem_ui/';
const cases = process.env.BINGO_LIVE_VISION_CASES
  ? JSON.parse(process.env.BINGO_LIVE_VISION_CASES)
  : [];
const resultTimeout = Number(process.env.BINGO_LIVE_VISION_TIMEOUT_MS || 150000);

async function installImageCamera(page, filePath) {
  const bytes = await fs.readFile(filePath);
  const extension = path.extname(filePath).toLowerCase();
  const mime = extension === '.png' ? 'image/png' : 'image/jpeg';
  const dataUrl = `data:${mime};base64,${bytes.toString('base64')}`;

  await page.addInitScript(({ source }) => {
    navigator.mediaDevices.getUserMedia = async constraints => {
      if (constraints.audio !== false) throw new Error('Audio must remain disabled');
      const image = new Image();
      image.src = source;
      await image.decode();
      const canvas = document.createElement('canvas');
      canvas.width = 640;
      canvas.height = 480;
      const context = canvas.getContext('2d');
      context.fillStyle = '#ffffff';
      context.fillRect(0, 0, canvas.width, canvas.height);
      const scale = Math.min(canvas.width / image.width, canvas.height / image.height);
      const width = image.width * scale;
      const height = image.height * scale;
      context.drawImage(image, (canvas.width - width) / 2, (canvas.height - height) / 2, width, height);
      return canvas.captureStream(15);
    };
  }, { source: dataUrl });
}

test('live AWS identification reaches the rendered Totem result', { skip: cases.length === 0 }, async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.BINGO_BROWSER_PATH || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    args: ['--use-fake-ui-for-media-stream'],
  });

  try {
    for (const visionCase of cases) {
      const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
      const diagnostics = [];
      page.on('console', message => diagnostics.push(`console:${message.type()}:${message.text()}`));
      page.on('requestfailed', request => diagnostics.push(`request:${request.url()}:${request.failure()?.errorText}`));
      page.on('response', response => {
        if (response.url().includes('/vision/analyze')) diagnostics.push(`response:${response.status()}`);
      });
      await installImageCamera(page, visionCase.file);
      await page.goto(`${url}?screen=camera&vision=remote`);
      await page.locator('[data-camera-action="start"]').click();
      await page.locator('[data-camera-action="capture"]').waitFor({ timeout: 20000 });
      await page.locator('[data-camera-action="capture"]').click();
      await page.locator('[data-camera-action="continue"]').waitFor();
      assert.match(await page.locator('[data-camera-status]').innerText(), /Analisar item/);
      if (process.env.BINGO_LIVE_VISION_CAPTURE_DIR) {
        await fs.mkdir(process.env.BINGO_LIVE_VISION_CAPTURE_DIR, { recursive: true });
        await page.locator('[data-camera-canvas]').screenshot({
          path: path.join(process.env.BINGO_LIVE_VISION_CAPTURE_DIR, `${path.basename(visionCase.file)}-captured.png`),
        });
      }
      await page.locator('[data-camera-action="continue"]').click();
      await page.locator('.screen--recognized, .screen--critical').waitFor({ timeout: resultTimeout });

      if (visionCase.expected === 'rejected') {
        assert.equal(await page.locator('.screen--critical').count(), 1, `${await page.locator('body').innerText()}\n${diagnostics.join('\n')}`);
        assert.match(await page.locator('.status-panel').innerText(), /devolver o item/i);
      } else {
        assert.equal(await page.locator('.screen--recognized').count(), 1, `${await page.locator('body').innerText()}\n${diagnostics.join('\n')}`);
        assert.match(await page.locator('.item-focus-footer').innerText(), new RegExp(visionCase.expected, 'i'));
        assert.match(await page.locator('.topbar .step').innerText(), /Reconhecimento/i);
      }
      await page.close();
    }
  } finally {
    await browser.close();
  }
});
