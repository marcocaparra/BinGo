const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("../../admin_web/node_modules/playwright");
const base = process.env.BINGO_CLOUD_TEST_URL;

test("cloud frontend and APIs require Basic Auth", async () => {
  assert.ok(base, "Run via cloud_http_smoke.py");
  for (const route of ["/", "/runtime.js", "/bingo/context"])
    assert.equal((await fetch(`${base}${route}`)).status, 401);
});

test("cloud uses same-origin, ignores visionUrl, omits catalog and supports upload/drop and deposit", async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.BINGO_BROWSER_PATH ||
      "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  });
  try {
    const context = await browser.newContext({
      httpCredentials: {
        username: "demo-fixture",
        password: "password-fixture",
      },
    });
    const page = await context.newPage();
    const errors = [];
    const operations = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("request", (request) => {
      const url = new URL(request.url());
      if (url.protocol === "blob:") return;
      assert.equal(url.origin, base);
      assert.ok(!url.pathname.startsWith("/assets/samples/"));
      if (
        url.pathname.startsWith("/bingo/") ||
        url.pathname.startsWith("/vision/")
      )
        operations.push({ path: url.pathname, data: request.postData() });
    });
    await page.goto(
      `${base}/?visionUrl=https://must-not-be-called.invalid/vision/analyze`,
    );
    await page
      .locator("#school-name")
      .filter({ hasText: "Escola cloud" })
      .waitFor();
    assert.equal(await page.evaluate(() => BinGoRuntime.mode), "cloud");
    assert.equal(await page.evaluate(() => BinGoSamples.length), 0);
    assert.equal(await page.locator(".sample-library").isVisible(), false);
    await page.locator("[data-discard-action=start]").click();
    await page.locator("[data-discard-action=anonymous]").click();
    await page.locator("[data-discard-action=class-next]").click();
    await page
      .locator("#item-image-input")
      .setInputFiles(path.join(__dirname, "../assets/samples/battery.png"));
    assert.equal(await page.locator("#item-image-preview").isVisible(), true);
    await page.locator("#retry-item-button").evaluate(() => {
      const data = new DataTransfer();
      data.items.add(
        new File([new Uint8Array([137, 80, 78, 71])], "manual-drop.png", {
          type: "image/png",
        }),
      );
      document
        .querySelector("#item-image-dropzone")
        .dispatchEvent(
          new DragEvent("drop", { dataTransfer: data, bubbles: true }),
        );
    });
    assert.match(
      await page.locator("#item-image-name").innerText(),
      /manual-drop.png/,
    );
    await page.locator("#analyze-item-button").click();
    await page.locator("#vision-result:not([hidden])").waitFor();
    await page.locator("#confirm-discard-button").click();
    await page.locator("#discard-screen-result:not([hidden])").waitFor();
    assert.match(
      await page.locator("#discard-result-card").innerText(),
      /456 XP/,
    );
    const deposit = JSON.parse(
      operations.find((op) => op.path === "/bingo/deposits").data,
    );
    assert.equal(deposit.student_id, null);
    assert.deepEqual(
      Object.keys(deposit).sort(),
      [
        "event_id",
        "class_id",
        "student_id",
        "is_valid",
        "detected_type",
        "waste_category_code",
        "category_source",
      ].sort(),
    );
    assert.ok(operations.some((op) => op.path === "/vision/analyze"));
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
});
