const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { installSupabaseFixture, submitLogin } = require('./test/supabase-fixture.cjs');
let browser;
before(async () => {
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.BINGO_BROWSER_PATH ||
      'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  });
});
after(async () => browser?.close());
async function open(role, run) {
  const page = await browser.newPage();
  try {
    const fixture = await installSupabaseFixture(page, { role, priceCap: 1500 });
    await page.goto(process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/');
    await page.getByLabel('Senha', { exact: true }).waitFor();
    assert.ok(!(await page.locator('app-access').innerText()).includes('Colégio ENIAC'));
    await page.getByText('Ambiente administrativo do BinGo', { exact: true }).waitFor();
    await submitLogin(page);
    await page.waitForFunction(() => {
      const button = Array.from(document.querySelectorAll('app-overview button')).find((b) =>
        b.textContent.includes('Atualizar visão geral'),
      );
      return button && !button.disabled;
    });
    await run(page, fixture);
  } finally {
    await page.close();
  }
}
for (const role of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C'])
  test(role + ' has backend identity and no fictitious school/operator in real areas', () =>
    open(role, async (page) => {
      const text = await page.locator('.admin-shell').innerText();
      for (const fake of ['Colégio ENIAC', 'Gustavo Alencar', 'Equipe BinGo'])
        assert.ok(!text.includes(fake), fake);
      await page.getByText('Administrador Autenticado', { exact: true }).waitFor();
      assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
      await page.getByRole('button', { name: 'Totens', exact: true }).click();
      await page.getByText('Totem RPC', { exact: true }).waitFor();
      await page.getByText('Somente leitura', { exact: true }).waitFor();
      assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
    }),
  );
for (const role of ['ADMIN_A', 'ADMIN_B'])
  test(role + ' missions remain explicitly demo, no CRUD or student RPC', () =>
    open(role, async (page, fixture) => {
      const reads = fixture.calls.length;
      await page.getByRole('button', { name: 'Missões', exact: true }).click();
      await page
        .getByText(/Leitura e gestão administrativa de Missões ainda não estão integradas/)
        .waitFor();
      await page.getByText('Modo demonstrativo', { exact: true }).waitFor();
      if (role === 'ADMIN_A') {
        await page.getByRole('button', { name: 'Criar missão global', exact: true }).click();
        const dialog = page.getByRole('dialog');
        await dialog.getByText('Dados demonstrativos', { exact: true }).waitFor();
        await dialog.getByLabel('Nome da missão').fill('Apenas em memória');
        await dialog.getByRole('button', { name: 'Criar missão', exact: true }).click();
        await page.getByText('Apenas em memória', { exact: true }).waitFor();
        await page.getByText(/concluído somente nesta demonstração/).waitFor();
      } else {
        assert.equal(await page.locator('app-missions').getByRole('button').count(), 0);
      }
      assert.equal(fixture.calls.length, reads);
    }),
  );
test('economy preserves real cap and labels remaining controls without persisting demo edits', () =>
  open('ADMIN_A', async (page, fixture) => {
    await page.getByRole('button', { name: 'Economia', exact: true }).click();
    await page.getByText('1500 BinCoins', { exact: true }).waitFor();
    await page.getByText(/Escopo e operações administrativas pendentes de contrato/).waitFor();
    const calls = fixture.calls.length;
    await page
      .locator('app-economy')
      .getByRole('button', { name: 'Editar', exact: true })
      .first()
      .click();
    const dialog = page.getByRole('dialog');
    await dialog.getByText('Dados demonstrativos', { exact: true }).waitFor();
    await dialog.getByLabel('Valor em pontos').fill('45');
    await dialog.getByRole('button', { name: 'Salvar regra', exact: true }).click();
    await page.getByText('45 pontos', { exact: true }).waitFor();
    assert.equal(fixture.calls.length, calls);
    assert.equal(fixture.priceCap, 1500);
    await page.getByText('1500 BinCoins', { exact: true }).waitFor();
  }));
for (const role of ['ADMIN_B', 'ADMIN_C'])
  test(role + ' help remains only demo and does not call a backend domain', () =>
    open(role, async (page, fixture) => {
      const calls = fixture.calls.length;
      await page.getByRole('button', { name: /Solicitações de ajuda/ }).click();
      await page.getByText('Modo demonstrativo', { exact: true }).waitFor();
      assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 1);
      await page.getByRole('button', { name: 'Assumir', exact: true }).click();
      await page.getByText(/marcado em atendimento somente nesta demonstração/).waitFor();
      assert.equal(fixture.calls.length, calls);
    }),
  );
