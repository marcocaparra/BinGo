/* Approved by the developer: current team design, not the migration baseline.
 * Read-only Git reference; no snapshot update mode and no image masks.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { createHash } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const revision = 'a9310a6eba3a979cc1349319d64656c0c7898064';
const repo = path.resolve(__dirname, '../../../..');
const referencePath = 'Software/apps/totem_ui';
const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.png': 'image/png', '.ttf': 'font/ttf' };
const fontAssets = new Set(['Software/mobile/bingo_app/assets/fonts/Sora[wght].ttf', 'Software/mobile/bingo_app/assets/fonts/Inter[opsz,wght].ttf', 'Software/mobile/bingo_app/assets/images/Praça Central - Limpa.png']);
const time = new Date('2026-10-31T12:00:00Z');
// Zero remains mandatory unless the developer explicitly approves otherwise.
const rasterAllowance = { pixels: 0, channelDifference: 0 };

async function freeze(page) {
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => [...document.images].every(image => image.complete));
  await page.evaluate(() => Promise.all([...document.images].map(image => image.decode())));
  await page.evaluate(() => {
    if ([...document.images].some(image => !image.naturalWidth)) throw new Error('Missing visual asset');
  });
}
async function animationContract(page) {
  return page.evaluate(() => [...document.querySelectorAll('#kiosk, #kiosk *')].flatMap(node => {
    const style = getComputedStyle(node);
    return style.animationName === 'none' ? [] : [{ tag: node.tagName, classes: [...node.classList].sort().join(' '), name: style.animationName, duration: style.animationDuration, delay: style.animationDelay, timing: style.animationTimingFunction, iterations: style.animationIterationCount }];
  }));
}
async function settleAnimations(page) {
  await page.evaluate(() => {
    for (const animation of document.getAnimations()) {
      if (Number.isFinite(animation.effect.getComputedTiming().endTime)) animation.finish();
      else { animation.pause(); animation.currentTime = 0; }
    }
  });
  // Drain compositor frames at the same virtual time on both pages. No CSS is
  // replaced, and no pixels/tolerances are excluded from the comparison.
  await page.clock.runFor(100);
}
async function layout(page) {
  return page.evaluate(() => [...document.querySelectorAll('#kiosk, #kiosk *')].map(node => {
    const rect = node.getBoundingClientRect(), style = getComputedStyle(node);
    return { tag: node.tagName, classes: [...node.classList].sort().join(' '), rect: [rect.x, rect.y, rect.width, rect.height], font: style.font, color: style.color, background: style.background, shadow: style.boxShadow, transform: style.transform, opacity: style.opacity, computed: Object.fromEntries([...style].map(key => [key, style.getPropertyValue(key)])) };
  }));
}
async function stableScreenshot(page) {
  await page.bringToFront();
  await page.evaluate(() => document.activeElement?.blur());
  let previous;
  for (let i = 0; i < 6; i++) {
    const current = await page.screenshot({ animations: 'disabled' });
    if (previous?.equals(current)) return current;
    previous = current;
    await page.clock.runFor(100);
  }
  throw new Error('Browser did not produce two identical consecutive frames');
}
async function designContract(page) {
  return page.evaluate(async () => {
    const urls = new Set();
    const assetName = url => decodeURIComponent(new URL(url, location.href).pathname).split('/assets/').pop().replace(/^images\//, 'backgrounds/');
    const normalized = value => value.replace(/url\("([^"]+)"\)/g, (_, url) => {
      urls.add(new URL(url, location.href).href);
      return 'asset(' + assetName(url) + ')';
    });
    const styles = (node, pseudo) => {
      const style = getComputedStyle(node, pseudo);
      return Object.fromEntries([...style].sort().map(key => [key, normalized(style.getPropertyValue(key))]));
    };
    const nodes = [...document.querySelectorAll('#kiosk, #kiosk *')];
    const structure = nodes.map(node => {
      const rect = node.getBoundingClientRect();
      if (node.tagName === 'IMG') urls.add(node.src);
      return {
        tag: node.tagName, parent: nodes.indexOf(node.parentElement), classes: [...node.classList].sort(),
        text: [...node.childNodes].filter(child => child.nodeType === Node.TEXT_NODE).map(child => child.textContent).join('').replace(/\s+/g, ' ').trim(),
        rect: [rect.x, rect.y, rect.width, rect.height],
        shape: Object.fromEntries(['d', 'points', 'viewBox', 'r', 'cx', 'cy', 'stroke', 'stroke-width', 'fill'].filter(key => node.hasAttribute(key)).map(key => [key, node.getAttribute(key)])),
        image: node.tagName === 'IMG' ? { decoding: node.decoding, draggable: node.draggable, alt: node.alt } : null,
        style: styles(node), before: styles(node, '::before'), after: styles(node, '::after'),
      };
    });
    const faces = [];
    for (const sheet of document.styleSheets) for (const rule of sheet.cssRules) {
      if (rule.type === CSSRule.FONT_FACE_RULE) {
        const properties = Object.fromEntries([...rule.style].sort().map(key => [key, key === 'src' ? rule.style.getPropertyValue(key).replace(/url\("([^"]+)"\)/g, (_, relative) => {
          const url = new URL(relative, sheet.href).href;
          urls.add(url); return 'asset(' + assetName(url) + ')';
        }) : rule.style.getPropertyValue(key)]));
        faces.push(properties);
      }
    }
    const assets = await Promise.all([...urls].map(async url => {
      if (new URL(url).origin !== location.origin) throw new Error('Nonlocal visual asset');
      const response = await fetch(url);
      if (!response.ok) throw new Error('Visual asset unavailable');
      const bytes = await response.arrayBuffer();
      const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(n => n.toString(16).padStart(2, '0')).join('');
      return { name: assetName(url), digest };
    }));
    assets.sort((a, b) => a.name.localeCompare(b.name));
    return { structure, faces, assets };
  });
}
async function pixelDifference(page, expected, actual) {
  return page.evaluate(async images => {
    const pixels = [];
    for (const src of images) {
      const image = new Image(); image.src = src; await image.decode();
      const canvas = document.createElement('canvas'); canvas.width = image.width; canvas.height = image.height;
      const context = canvas.getContext('2d'); context.drawImage(image, 0, 0);
      pixels.push(context.getImageData(0, 0, canvas.width, canvas.height).data);
    }
    let changed = 0, maximum = 0;
    for (let i = 0; i < pixels[0].length; i += 4) {
      let different = false;
      for (let c = 0; c < 4; c++) {
        const delta = Math.abs(pixels[0][i + c] - pixels[1][i + c]);
        if (delta) different = true;
        maximum = Math.max(maximum, delta);
      }
      if (different) changed++;
    }
    return { changed_pixels: changed, maximum_channel_difference: maximum };
  }, [expected, actual].map(buffer => 'data:image/png;base64,' + buffer.toString('base64')));
}
async function openApprovedVisual(context, output, data) {
  const results = [], cache = new Map();
  const server = http.createServer((req, res) => {
    try {
      assert.equal(req.method, 'GET');
      let file = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).slice(1);
      if (file.endsWith('/')) file += 'index.html';
      assert.ok(!file.includes('..') && (file.startsWith(referencePath + '/') || fontAssets.has(file)));
      if (!cache.has(file)) cache.set(file, execFileSync('git', ['show', revision + ':' + file], { cwd: repo, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16000000 }));
      res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
      res.end(cache.get(file));
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = 'http://127.0.0.1:' + server.address().port;
  let page;
  try {
    page = await context.newPage();
    await page.route('**/*', route => {
      assert.equal(new URL(route.request().url()).origin, origin);
      return route.continue();
    });
    await page.clock.install({ time });
    await page.clock.pauseAt(new Date(time.getTime() + 60000));
    return {
      results, revision, referencePath,
      async compare(actualPage, screen, options = {}) {
        await page.goto(origin + '/' + referencePath + '/?screen=' + screen, { waitUntil: 'networkidle' });
        // Equal synthetic content, using the reference's own data and renderers.
        // These assignments change labels/records only; no layout or CSS patching.
        await page.evaluate(({ screen, data, options }) => {
          for (const key of Object.keys(schoolTree)) delete schoolTree[key];
          for (const segment of [...new Set(data.classes.map(c => c.segment).filter(Boolean))]) {
            schoolTree[segment] = { label: segment, speech: 'Agora escolha o seu ano.', years: [...new Set(data.classes.filter(c => c.segment === segment).map(c => c.grade).filter(Boolean))] };
          }
          selectedSegment = data.classes[0].segment;
          selectedYear = data.classes[0].grade;
          classLetters.splice(0, classLetters.length, ...data.classes.map(c => c.name));
          students.splice(0, students.length, ...data.students.map(s => s.name));
          currentIndex = screens.findIndex(s => s.id === screen);
          selectedStudent = data.students[0].name;
          if (options.itemId) recognizedItem = itemOptions.find(item => item.id === options.itemId);
          searchQuery = options.filter || '';
          searchActive = Boolean(options.searchActive);
          keyboardShift = true;
          pinDigits = options.pinLength || 0;
          pinSetupStep = 'login';
          pinWarning = Boolean(options.warning);
          pinErrorMessage = options.warning || '';
          render();
          if (options.notice) document.querySelector('.guide-bubble').textContent = options.notice;
          if (options.disableCorrection) document.querySelector('[data-correction-open]').disabled = true;
          if (options.disableCancel) document.querySelector('[data-cancel-discard]').disabled = true;
          if (screen === 'class') document.querySelectorAll('.class-list button span').forEach((node, i) => { node.textContent = data.classes[i].name; });
        }, { screen, data, options });
        // Match pointer state too: a prior click must not leave only one side
        // hovering a button. This changes no pixels through CSS or masking.
        await page.mouse.move(0, 0); await actualPage.mouse.move(0, 0);
        await freeze(page); await freeze(actualPage);
        assert.deepEqual(await animationContract(actualPage), await animationContract(page), 'Animation definitions must remain unchanged');
        await settleAnimations(page); await settleAnimations(actualPage);
        const name = options.name || screen;
        const expected = await stableScreenshot(page);
        const actual = await stableScreenshot(actualPage);
        fs.writeFileSync(path.join(output, 'approved-' + name + '-reference.png'), expected);
        fs.writeFileSync(path.join(output, 'approved-' + name + '-actual.png'), actual);
        const hash = buffer => createHash('sha256').update(buffer).digest('hex');
        const referenceDesign = await designContract(page), actualDesign = await designContract(actualPage);
        const designEqual = JSON.stringify(referenceDesign) === JSON.stringify(actualDesign);
        const pixels = await pixelDifference(page, expected, actual);
        const result = { screen: name, expected: hash(expected), actual: hash(actual), equal: expected.equals(actual), design_equal: designEqual, ...pixels, raster_allowance: rasterAllowance, passed: designEqual && pixels.changed_pixels <= rasterAllowance.pixels && pixels.maximum_channel_difference <= rasterAllowance.channelDifference };
        results.push(result);
        if (!designEqual) fs.writeFileSync(path.join(output, 'approved-' + name + '-design.json'), JSON.stringify({ reference: referenceDesign, actual: actualDesign }, null, 2));
        if (!result.equal) fs.writeFileSync(path.join(output, 'approved-' + name + '-layout.json'), JSON.stringify({ reference: await layout(page), actual: await layout(actualPage) }, null, 2));
        // Aggregate pixel failures after the functional scenarios, never turn
        // a discrepancy into a newly accepted reference.
      },
      async close() {
        await page.close();
        // The reference page is closed; no request may outlive this owned
        // server. Chromium may retain a speculative keep-alive connection.
        const closed = new Promise(resolve => server.close(resolve));
        server.closeAllConnections();
        await closed;
      },
    };
  } catch (error) {
    if (page) await page.close();
    const closed = new Promise(resolve => server.close(resolve));
    server.closeAllConnections();
    await closed;
    throw error;
  }
}
module.exports = { openApprovedVisual, time };
