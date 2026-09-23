const { test } = require("node:test");
const assert = require("node:assert/strict");
const { chromium } = require("playwright");

const url = process.env.BINGO_ADMIN_URL || "http://127.0.0.1:8105/apps/admin_web/";
const browserOptions = {
  headless: true,
  executablePath: process.env.BINGO_BROWSER_PATH || "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
};

async function openAdmin(page) {
  await page.goto(url);
  await page.getByRole("button", { name: "Acessar o Admin" }).click();
  await page.getByRole("heading", { name: "Operação de hoje" }).waitFor();
}

async function assertNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    viewport: document.documentElement.clientWidth,
    content: document.documentElement.scrollWidth,
  }));
  assert.ok(dimensions.content <= dimensions.viewport, `overflow horizontal: ${dimensions.content}px em ${dimensions.viewport}px`);
}

test("access screen opens the demonstrative operational overview", async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await page.goto(url);
    assert.equal(await page.getByText("Ambiente demonstrativo.", { exact: false }).count(), 1);
    await openAdmin(page);
    assert.equal(await page.getByText("Dados demonstrativos", { exact: true }).count(), 1);
    assert.equal(await page.getByText("1.284", { exact: true }).count(), 1);
    assert.equal(await page.getByText("32 hoje · 184 nesta semana", { exact: true }).count(), 1);
  } finally {
    await browser.close();
  }
});

test("primary views and demonstrative states are navigable", async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
    await openAdmin(page);

    await page.getByRole("button", { name: "Descartes", exact: true }).click();
    await page.getByRole("heading", { name: "Descartes recentes" }).waitFor();
    assert.equal(await page.getByRole("columnheader", { name: "Aluno ou perfil" }).count(), 1);

    await page.getByRole("button", { name: /Solicitações de ajuda/ }).click();
    await page.getByRole("heading", { name: "Solicitações de ajuda" }).waitFor();
    await page.getByRole("button", { name: "Assumir" }).click();
    await page.getByText(/marcado em atendimento/).waitFor();

    await page.getByRole("button", { name: /Resgates/ }).click();
    await page.getByRole("heading", { name: "Resgates pendentes" }).waitFor();
    await page.getByRole("button", { name: "Validar entrega" }).first().click();
    await page.getByRole("dialog").getByRole("button", { name: "Confirmar entrega" }).click();
    await page.getByText(/entregue somente nesta demonstração/).waitFor();

    await page.getByRole("button", { name: "Totens" }).click();
    await page.getByRole("heading", { name: "Estado dos Totens" }).waitFor();
    assert.equal(await page.getByText("Totem Biblioteca", { exact: true }).count(), 1);
    assert.equal(await page.getByText("Com problema", { exact: true }).count(), 1);
    assert.equal(await page.locator(".last-seen").count(), 3);
    await assert.doesNotReject(() => page.locator(".last-seen").first().getByText(/Última comunicação/).waitFor());

    await page.getByLabel("Cenário da demonstração").selectOption("error");
    await page.getByRole("heading", { name: "Não foi possível atualizar" }).waitFor();
    await page.getByRole("button", { name: "Tentar novamente" }).click();
    await page.getByText(/carregados novamente/).waitFor();
  } finally {
    await browser.close();
  }
});

test("admin stays contained at school tablet and narrow widths", async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    for (const viewport of [
      { width: 420, height: 720 },
      { width: 480, height: 800 },
      { width: 600, height: 1024 },
    ]) {
      const page = await browser.newPage({ viewport });
      await page.goto(url);
      await assertNoHorizontalOverflow(page);
      await openAdmin(page);
      await assertNoHorizontalOverflow(page);

      for (const name of ["Descartes", /Solicitações de ajuda/, /Resgates/, "Totens"]) {
        await page.getByRole("button", { name, exact: typeof name === "string" }).click();
        await assertNoHorizontalOverflow(page);
      }
      await page.close();
    }
  } finally {
    await browser.close();
  }
});
