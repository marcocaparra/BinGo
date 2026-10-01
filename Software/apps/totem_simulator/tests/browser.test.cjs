const { test } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("../../admin_web/node_modules/playwright");
const base =
  process.env.BINGO_TOTEM_TEST_FRONTEND_URL || "http://127.0.0.1:8110";
const local = "http://127.0.0.1:8765";
const classId = "20000000-0000-4000-8000-000000000001";
const studentId = "30000000-0000-4000-8000-000000000001";
const sample = path.join(__dirname, "../assets/samples/battery.png");
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function setup(overrides = {}) {
  const browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.BINGO_BROWSER_PATH ||
      "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  });
  const context = await browser.newContext();
  const page = await context.newPage();
  const calls = [];
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  let studentBalance = 17;
  let classBalance = 31;
  const student = () => ({
    id: studentId,
    name: "Ana real",
    class_id: classId,
    class_name: "Turma real",
    status: "ACTIVE",
    points_student_balance: studentBalance,
  });
  const classroom = () => ({
    id: classId,
    name: "Turma real",
    segment: "Fundamental",
    grade: "6",
    points_class_balance: classBalance,
  });
  await page.route(`${local}/bingo/**`, async (route) => {
    const request = route.request();
    const operation = new URL(request.url()).pathname.split("/").pop();
    const payload = request.postDataJSON();
    assert.equal(request.headers()["x-api-key"], undefined);
    assert.equal(request.headers()["x-machine-id"], undefined);
    calls.push({ operation, payload });
    if (overrides[operation])
      return overrides[operation](route, payload, calls);
    let body;
    let status = 200;
    if (operation === "health")
      body = { status: "AVAILABLE", can_start_deposit: true };
    if (operation === "context")
      body = {
        school: {
          id: "10000000-0000-4000-8000-000000000001",
          name: "Escola real",
        },
        machine: { id: "40000000-0000-4000-8000-000000000001", name: "Totem" },
        classes: [classroom()],
        students: [student()],
      };
    if (operation === "rankings")
      body = { students: [student()], classes: [classroom()] };
    if (operation === "student-summary")
      body = {
        student: student(),
        stats: {
          valid_deposits_count: 2,
          invalid_deposits_count: 1,
          total_bins_generated: 123,
        },
        recent_deposits: [],
      };
    if (operation === "student-pin")
      body =
        payload.pin === "4827"
          ? { confirmed: true, student: student() }
          : { error: { message: "PIN não confirmado" } };
    if (operation === "student-pin" && payload.pin !== "4827") status = 401;
    if (operation === "deposits") {
      studentBalance += payload.student_id ? 123 : 0;
      classBalance += 456;
      status = 201;
      body = {
        id: "b0000000-0000-4000-8000-000000000001",
        event_id: payload.event_id,
        points_awarded_student: payload.student_id ? 123 : 0,
        bonus_bincoins_awarded: payload.student_id ? 23 : 0,
        points_awarded_class: 456,
        waste_category_code: payload.waste_category_code,
      };
    }
    await route.fulfill({ status, json: body });
  });
  await page.route(`${local}/vision/analyze**`, async (route) => {
    if (overrides.vision) return overrides.vision(route);
    await route.fulfill({
      json: {
        status: "recognized",
        itemId: "battery",
        candidateIds: ["battery"],
        confidence: 0.98,
        origin: "AWS_REKOGNITION",
      },
    });
  });
  await page.goto(base);
  await page
    .locator("#school-name")
    .filter({ hasText: "Escola real" })
    .waitFor();
  await page.locator("[data-discard-action=start]").waitFor();
  return { browser, page, calls, errors, context };
}
async function identify(page, pin = "4827") {
  await page.locator("[data-discard-action=start]").click();
  await page.locator("[data-discard-action=identified]").click();
  await page.locator("#identified-class-select").selectOption(classId);
  await page.locator("#student-picker-open").click();
  await page
    .locator(`#student-picker-list [data-student-id="${studentId}"]`)
    .click();
  await page.locator("#student-pin").fill(pin);
  await page.locator("[data-discard-action=validate-student]").click();
}
async function analyze(page) {
  await page.locator("#item-image-input").setInputFiles(sample);
  await page.locator("#analyze-item-button").click();
  await page.locator("#vision-result:not([hidden])").waitFor();
}
test("real-contract identified flow, backend rewards, summary, rankings and preserved 15-image library", async () => {
  const { browser, page, calls, errors } = await setup();
  try {
    assert.equal(
      await page.locator("#sample-grid [data-sample-id]").count(),
      15,
    );
    await identify(page);
    await page.locator("#discard-screen-item:not([hidden])").waitFor();
    assert.equal(await page.locator("#student-pin").inputValue(), "");
    await analyze(page);
    await page.locator("#confirm-discard-button").click();
    await page.locator("#discard-screen-result:not([hidden])").waitFor();
    assert.match(await page.locator("#discard-result-card").innerText(), /123/);
    assert.match(
      await page.locator("#discard-result-card").innerText(),
      /456 XP/,
    );
    assert.match(await page.locator("#discard-result-card").innerText(), /23/);
    const payload = calls.find(
      (entry) => entry.operation === "deposits",
    ).payload;
    assert.deepEqual(
      Object.keys(payload).sort(),
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
    assert.equal(payload.category_source, "AI_CONFIRMED");
    assert.equal(payload.waste_category_code, "BATTERY");
    assert.equal(
      await page.evaluate(() => localStorage.getItem(BinGoBackend.PENDING_KEY)),
      null,
    );
    await page.locator("[data-section=ranking-section]").click();
    await page
      .locator("#student-ranking")
      .filter({ hasText: "Ana real" })
      .waitFor();
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
});
test("invalid PIN never advances, returns no token and clears PIN", async () => {
  const { browser, page, calls } = await setup();
  try {
    await identify(page, "0000");
    await page
      .locator("#discard-message")
      .filter({ hasText: "PIN não confirmado" })
      .waitFor();
    assert.equal(await page.locator("#discard-screen-item").isVisible(), false);
    assert.equal(await page.locator("#student-pin").inputValue(), "");
    assert.equal(
      calls.some((entry) => entry.operation === "deposits"),
      false,
    );
  } finally {
    await browser.close();
  }
});
test("readiness failure blocks cycle and never promises points", async () => {
  const { browser, page, calls } = await setup({
    health: (route) =>
      route.fulfill({
        status: 503,
        json: { error: { message: "Backend indisponível" } },
      }),
  });
  try {
    await page.locator("[data-discard-action=start]").click();
    await page
      .locator("#discard-message")
      .filter({ hasText: "Novo descarte bloqueado" })
      .waitFor();
    assert.equal(await page.locator("#discard-screen-mode").isVisible(), false);
    assert.equal(
      calls.some((entry) => entry.operation === "deposits"),
      false,
    );
  } finally {
    await browser.close();
  }
});
test("AI technical failure and missing confirmation are not rejected deposits", async () => {
  for (const secondary of [501, 502]) {
    const { browser, page, calls } = await setup({
      vision: (route) =>
        new URL(route.request().url()).searchParams.get("stage") === "primary"
          ? route.fulfill({
              json: {
                status: "needs-secondary",
                candidateIds: ["battery"],
                confidence: 0.4,
                origin: "AWS_REKOGNITION",
              },
            })
          : route.fulfill({
              status: secondary,
              json: { error: "secondary_provider_unavailable" },
            }),
    });
    try {
      await identify(page);
      await page.locator("#discard-screen-item:not([hidden])").waitFor();
      await page.locator("#item-image-input").setInputFiles(sample);
      await page.locator("#analyze-item-button").click();
      await page
        .locator("#vision-analysis-title")
        .filter({ hasText: "Não foi possível analisar" })
        .waitFor();
      assert.equal(
        await page.locator("#confirm-discard-button").isVisible(),
        false,
      );
      assert.equal(
        calls.some((entry) => entry.operation === "deposits"),
        false,
      );
    } finally {
      await browser.close();
    }
  }
});
test("unknown result survives reload and reuses exact event; no new cycle while pending", async () => {
  let attempts = 0;
  let original;
  const { browser, page } = await setup({
    deposits: async (route, payload) => {
      attempts++;
      if (attempts === 1) {
        original = payload;
        await route.abort("timedout");
      } else {
        assert.deepEqual(payload, original);
        await route.fulfill({
          status: 200,
          json: {
            id: "b0000000-0000-4000-8000-000000000001",
            event_id: payload.event_id,
            points_awarded_student: 123,
            points_awarded_class: 456,
            bonus_bincoins_awarded: 23,
          },
        });
      }
    },
  });
  try {
    await identify(page);
    await page.locator("#discard-screen-item:not([hidden])").waitFor();
    await analyze(page);
    await page.locator("#confirm-discard-button").click();
    await page
      .locator("#pending-recovery-message")
      .filter({ hasText: "pontuação ainda não foi confirmada" })
      .waitFor();
    assert.deepEqual(
      await page.evaluate(() =>
        JSON.parse(localStorage.getItem(BinGoBackend.PENDING_KEY)),
      ),
      original,
    );
    await page.reload();
    await page.locator("#pending-recovery:not([hidden])").waitFor();
    assert.equal(
      await page.locator("[data-discard-action=start]").isDisabled(),
      true,
    );
    await page.locator("#retry-pending-button").click();
    await page.locator("#discard-screen-result:not([hidden])").waitFor();
    assert.equal(attempts, 2);
    assert.equal(
      await page.evaluate(() => localStorage.getItem(BinGoBackend.PENDING_KEY)),
      null,
    );
  } finally {
    await browser.close();
  }
});
test("post-confirmation read failure does not turn committed deposit into an unknown result", async () => {
  let committed = false;
  const { browser, page, calls } = await setup({
    deposits: async (route, payload) => {
      committed = true;
      await route.fulfill({
        status: 201,
        json: {
          id: "b0000000-0000-4000-8000-000000000001",
          event_id: payload.event_id,
          points_awarded_student: 123,
          points_awarded_class: 456,
          bonus_bincoins_awarded: 23,
        },
      });
    },
    context: async (route) =>
      route.fulfill(
        committed
          ? { status: 500, json: { error: { message: "Read failed" } } }
          : {
              json: {
                school: { name: "Escola real" },
                classes: [{ id: classId, name: "Turma real" }],
                students: [
                  { id: studentId, name: "Ana real", class_id: classId },
                ],
              },
            },
      ),
  });
  try {
    await identify(page);
    await page.locator("#discard-screen-item:not([hidden])").waitFor();
    await analyze(page);
    await page.locator("#confirm-discard-button").click();
    await page.locator("#discard-screen-result:not([hidden])").waitFor();
    assert.match(
      await page.locator("#discard-result-card").innerText(),
      /Consulta indisponível/,
    );
    assert.equal(
      await page.evaluate(() => localStorage.getItem(BinGoBackend.PENDING_KEY)),
      null,
    );
    assert.equal(
      calls.filter((entry) => entry.operation === "deposits").length,
      1,
    );
  } finally {
    await browser.close();
  }
});
test("class-only uses null student; backend failure before drop creates no pending event", async () => {
  let checks = 0;
  const { browser, page, calls } = await setup({
    health: (route) =>
      route.fulfill(
        ++checks === 1
          ? { json: { status: "AVAILABLE", can_start_deposit: true } }
          : { status: 500, json: { error: { message: "Down before drop" } } },
      ),
  });
  try {
    await page.locator("[data-discard-action=start]").click();
    await page.locator("[data-discard-action=anonymous]").click();
    await page.locator("[data-discard-action=class-next]").click();
    await analyze(page);
    await page.locator("#confirm-discard-button").click();
    await page
      .locator("#discard-message")
      .filter({ hasText: "Item não recebido" })
      .waitFor();
    assert.equal(
      await page.evaluate(() => localStorage.getItem(BinGoBackend.PENDING_KEY)),
      null,
    );
    assert.equal(
      calls.some((entry) => entry.operation === "deposits"),
      false,
    );
  } finally {
    await browser.close();
  }
});
test(
  "local Supabase + trusted service + browser smoke with controlled original vision boundary",
  { skip: process.env.BINGO_TOTEM_BROWSER_INTEGRATION !== "1" },
  async () => {
    const browser = await chromium.launch({
      headless: true,
      executablePath:
        process.env.BINGO_BROWSER_PATH ||
        "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    });
    const page = await browser.newPage();
    if (process.env.BINGO_TOTEM_TEST_GATEWAY_URL) {
      // Test-only forwarding lets the real smoke use an isolated loopback port
      // while the application keeps its default :8765 URL unchanged.
      const gateway = new URL(process.env.BINGO_TOTEM_TEST_GATEWAY_URL);
      assert.equal(gateway.hostname, "127.0.0.1");
      await page.route(`${local}/**`, async (route) => {
        const response = await route.fetch({
          url: route.request().url().replace(local, gateway.origin),
        });
        await route.fulfill({ response });
      });
    }
    const events = [];
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("request", (request) => {
      if (request.url() === `${local}/bingo/deposits`) {
        assert.equal(request.headers()["x-api-key"], undefined);
        events.push(request.postDataJSON());
      }
    });
    try {
      await page.goto(base);
      await page
        .locator("#school-name")
        .filter({ hasText: "Escola Demo BinGo" })
        .waitFor();
      await identify(page);
      await page.locator("#discard-screen-item:not([hidden])").waitFor();
      await analyze(page);
      await page.locator("#confirm-discard-button").click();
      await page.locator("#discard-screen-result:not([hidden])").waitFor();
      const snapshot = await page.evaluate(
        async (payload) => await backend.request("deposits", payload),
        events[0],
      );
      assert.match(
        await page.locator("#discard-result-card").innerText(),
        new RegExp(String(snapshot.points_awarded_student)),
      );
      assert.equal(events[0].student_id, studentId);
      await page.locator("[data-discard-action=new-discard]").click();
      await page.locator("[data-discard-action=anonymous]").click();
      await page.locator("[data-discard-action=class-next]").click();
      await analyze(page);
      await page.locator("#confirm-discard-button").click();
      await page.locator("#discard-screen-result:not([hidden])").waitFor();
      assert.equal(events.at(-1).student_id, null);
      assert.deepEqual(errors, []);
      console.log(
        "SMOKE_EVENTS=" +
          JSON.stringify([...new Set(events.map((event) => event.event_id))]),
      );
    } finally {
      await browser.close();
    }
  },
);
