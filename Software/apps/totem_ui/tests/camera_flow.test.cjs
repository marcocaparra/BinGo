const { test } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const fs = require('node:fs/promises');
const path = require('node:path');

const url = process.env.BINGO_TOTEM_URL || 'http://127.0.0.1:8105/apps/totem_ui/';
const browserOptions = {
  headless: true,
  executablePath: process.env.BINGO_BROWSER_PATH || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'],
};

async function activateSyntheticCamera(page) {
  for (let attempt = 0; attempt < 2; attempt++) {
    await page.locator('[data-camera-action="start"]').click();
    try {
      await page.locator('[data-camera-action="capture"]').waitFor({ timeout: 20000 });
      return;
    } catch (error) {
      if (attempt === 1) throw error;
      await page.locator('[data-camera-action="start"]').waitFor();
    }
  }
}

async function installSyntheticCamera(page) {
  await page.addInitScript(() => {
    navigator.mediaDevices.getUserMedia = async constraints => {
      if (constraints.audio !== false) throw new Error('Audio must remain disabled');
      const canvas = document.createElement('canvas');
      canvas.width = 640;
      canvas.height = 480;
      const context = canvas.getContext('2d');
      context.fillStyle = '#00aeef';
      context.fillRect(0, 0, canvas.width, canvas.height);
      context.fillStyle = '#ffffff';
      context.fillRect(220, 140, 200, 200);
      window.__bingoSyntheticCamera = canvas;
      return canvas.captureStream(15);
    };
  });
}

test('camera flow with synthetic device, responsive layouts and simulated AI', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const output = path.join(__dirname, '../_visual_check_local');
    await fs.mkdir(output, { recursive: true });
    for (const viewport of [{ width: 420, height: 720 }, { width: 480, height: 800 }, { width: 600, height: 1024 }]) {
      for (const fontScale of [1, 2]) {
      const page = await browser.newPage({ viewport });
      await installSyntheticCamera(page);
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.goto(url + '?screen=safety');
      await page.locator('[data-safety-safe]').click();
      await page.locator('[data-item-inserted]').click();
      await page.locator('[data-hand-confirmed]').click();
      await page.locator('[data-camera-action="start"]').waitFor();
      assert.equal(await page.locator('[data-camera-video]').evaluate(video => video.srcObject), null);
      await page.waitForTimeout(3000);
      assert.equal(await page.locator('.screen--real-camera').count(), 1);
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map(image => image.decode().catch(() => {})));
      });
      if (fontScale === 2) {
        await page.evaluate(() => {
          document.querySelectorAll('.camera-actions button, .camera-status, .camera-placeholder, .camera-bar, .camera-bar strong, .simulation-badge, .guide-bubble').forEach(element => {
            element.style.fontSize = `${parseFloat(getComputedStyle(element).fontSize) * 2}px`;
          });
        });
      }
      await page.screenshot({ path: path.join(output, `camera-idle-${viewport.width}-font-${fontScale}x.png`), fullPage: true });
      await activateSyntheticCamera(page);
      assert.equal(await page.locator('[data-camera-video]').evaluate(video => video.videoWidth > 0 && video.srcObject.getAudioTracks().length === 0), true);
      await page.screenshot({ path: path.join(output, `camera-live-${viewport.width}-font-${fontScale}x.png`), fullPage: true });
      await page.locator('[data-camera-action="capture"]').click();
      await page.locator('[data-camera-action="continue"]').waitFor();
      await page.evaluate(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map(image => image.decode().catch(() => {})));
      });
      assert.equal(await page.locator('[data-camera-canvas]').evaluate(canvas => canvas.width > 0 && canvas.height > 0), true);
      assert.equal(await page.locator('[data-camera-video]').evaluate(video => video.srcObject), null);
      const layout = await page.evaluate(() => {
        const screen = document.querySelector('.screen');
        const button = document.querySelector('[data-camera-action]');
        const box = button.getBoundingClientRect();
        return { overflow: screen.scrollWidth - screen.clientWidth, actionVisible: box.bottom <= innerHeight && box.top >= 0 };
      });
      assert.ok(layout.overflow <= 1, JSON.stringify(layout));
      assert.ok(layout.actionVisible, JSON.stringify(layout));
      await page.locator('.content-zone--camera').evaluate(zone => { zone.scrollTop = zone.scrollHeight; });
      await page.screenshot({ path: path.join(output, `camera-captured-${viewport.width}-font-${fontScale}x.png`), fullPage: true });
      await page.locator('[data-camera-retake]').click();
      await page.locator('[data-camera-action="capture"]').waitFor();
      await page.locator('[data-camera-action="capture"]').click();
      await page.locator('[data-camera-action="continue"]').click();
      await page.locator('.screen--analysis').waitFor();
      assert.match(await page.locator('.simulation-badge').innerText(), /simulado/);
      assert.deepEqual(errors, []);
      await page.close();
      }
    }
  } finally {
    await browser.close();
  }
});

test('permission denied stays on camera and offers retry/devolution', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    await page.addInitScript(() => {
      navigator.mediaDevices.getUserMedia = async () => { throw new DOMException('Denied for test', 'NotAllowedError'); };
    });
    await page.goto(url + '?screen=camera');
    await page.locator('[data-camera-action="start"]').click();
    await page.getByRole('button', { name: 'Tentar novamente' }).waitFor();
    assert.match(await page.locator('[data-camera-status]').innerText(), /Permissão negada/);
    assert.equal(await page.locator('[data-camera-action="continue"]').count(), 0);
    await page.locator('[data-return-start]').click();
    await page.locator('[data-auto-next="return-confirm"]').waitFor();
  } finally {
    await browser.close();
  }
});

test('explicit camera simulation preserves the old demo without requesting webcam', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage();
    await page.addInitScript(() => {
      navigator.mediaDevices.getUserMedia = () => { throw new Error('Simulation must not open a device'); };
    });
    await page.goto(url + '?screen=camera&camera=simulated');
    assert.equal(await page.locator('[data-camera-video]').count(), 0);
    await page.locator('.screen--analysis').waitFor();
    assert.match(await page.locator('.simulation-badge').innerText(), /simulado/);
  } finally {
    await browser.close();
  }
});

test('vision provider keeps success, secondary analysis and rejection flows deterministic', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));

    await page.goto(url + '?screen=camera&camera=simulated&scenario=success');
    await page.locator('.screen--recognized').waitFor();
    assert.match(await page.locator('.item-focus-footer').innerText(), /Cabo/);

    await page.goto(url + '?screen=camera&camera=simulated&scenario=uncertain');
    await page.locator('.analysis-progress--secondary').waitFor();
    await page.locator('.screen--recognized').waitFor();
    assert.match(await page.locator('.item-focus-footer').innerText(), /Cabo/);

    await page.goto(url + '?screen=camera&camera=simulated&scenario=rejected');
    await page.locator('.screen--critical').waitFor();
    assert.match(await page.locator('.status-panel').innerText(), /devolver o item/i);
    assert.equal(await page.locator('[data-adjust-retry]').innerText(), 'Ajustar item e tentar de novo');
    await page.locator('[data-adjust-retry]').click();
    await page.locator('.screen--insert').waitFor({ timeout: 5000 });
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
});

test('real captured frame remains available through secondary analysis', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 420, height: 720 } });
    await installSyntheticCamera(page);
    await page.goto(url + '?screen=camera&scenario=uncertain');
    await activateSyntheticCamera(page);
    await page.locator('[data-camera-action="capture"]').click();
    await page.locator('[data-camera-action="continue"]').click();
    await page.locator('.analysis-progress--secondary').waitFor();
    await page.locator('.screen--recognized').waitFor();
    assert.match(await page.locator('.item-focus-footer').innerText(), /Cabo/);
  } finally {
    await browser.close();
  }
});
