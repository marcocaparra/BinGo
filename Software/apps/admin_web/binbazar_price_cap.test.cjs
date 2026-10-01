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
async function open(role, options = {}) {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, { role, ...options });
  await page.goto(process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/');
  await submitLogin(page);
  await page
    .getByRole('button', {
      name: role === 'ADMIN_A' ? 'Economia' : 'Produtos e estoque',
      exact: true,
    })
    .click();
  return { page, fixture };
}
async function fillProduct(page, name, price) {
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Produto', { exact: true }).fill(name);
  await dialog.getByLabel('Preço em BinCoins').fill(String(price));
  await dialog.getByLabel('Categoria').fill('Material escolar');
  return dialog;
}
test('A defines first cap without demo 300 or optimistic confirmation, then edits it', async () => {
  let release;
  const wait = new Promise((r) => (release = r));
  const { page, fixture } = await open('ADMIN_A', { capMutationWait: wait });
  try {
    const cap = page.locator('app-binbazar-price-cap');
    await cap.getByText('Ainda não configurado', { exact: true }).waitFor();
    assert.equal(await cap.getByText('300 BinCoins', { exact: true }).count(), 0);
    await page.getByText('Outras configurações — Dados demonstrativos', { exact: true }).waitFor();
    await cap.getByRole('button', { name: 'Definir teto' }).click();
    const dialog = page.getByRole('dialog');
    assert.equal(await dialog.getByLabel('Teto máximo em BinCoins').inputValue(), '');
    await dialog.getByLabel('Teto máximo em BinCoins').fill('1500');
    await dialog.getByRole('button', { name: 'Salvar teto' }).click();
    await dialog.getByRole('button', { name: 'Salvando…' }).waitFor();
    assert.equal(await cap.getByText('Teto global atualizado.', { exact: true }).count(), 0);
    assert.equal(fixture.priceCap, null);
    release();
    await cap.getByText('1500 BinCoins', { exact: true }).waitFor();
    await cap.getByRole('button', { name: 'Editar teto' }).click();
    await dialog.getByLabel('Teto máximo em BinCoins').fill('1000');
    await dialog.getByRole('button', { name: 'Salvar teto' }).click();
    await cap.getByText('1000 BinCoins', { exact: true }).waitFor();
    const updates = fixture.calls.filter((c) => c.path.endsWith('update_binbazar_price_cap_v1'));
    assert.deepEqual(
      updates.map((c) => c.body),
      [{ p_max_price: 1500 }, { p_max_price: 1000 }],
    );
  } finally {
    release();
    await page.close();
  }
});
test('A loading/read failure and failed update have no demo fallback or success', async () => {
  let release;
  const { page, fixture } = await open('ADMIN_A', {
    capWait: new Promise((r) => (release = r)),
    capError: true,
  });
  try {
    const cap = page.locator('app-binbazar-price-cap');
    await cap.getByText('Carregando teto global', { exact: true }).waitFor();
    release();
    await cap.getByText('Não foi possível carregar o teto', { exact: true }).waitFor();
    assert.equal(await cap.getByRole('button', { name: 'Definir teto' }).count(), 0);
    fixture.capError = false;
    fixture.priceCap = 1200;
    await cap.getByRole('button', { name: 'Tentar novamente' }).click();
    await cap.getByText('1200 BinCoins', { exact: true }).waitFor();
    fixture.capMutationError = true;
    await cap.getByRole('button', { name: 'Editar teto' }).click();
    await page.getByLabel('Teto máximo em BinCoins').fill('900');
    await page.getByRole('button', { name: 'Salvar teto' }).click();
    await page
      .getByRole('alert')
      .getByText(/Não foi possível salvar o teto/)
      .waitFor();
    assert.equal(fixture.priceCap, 1200);
    assert.equal(await cap.getByText('Teto global atualizado.', { exact: true }).count(), 0);
    assert.equal(await page.getByRole('dialog').count(), 1);
  } finally {
    release();
    await page.close();
  }
});
for (const role of ['ADMIN_B', 'ADMIN_C']) {
  test(
    role + ' creates and edits real product/category/price with UUID, null stock and refetch',
    async () => {
      const { page, fixture } = await open(role, { priceCap: 1500 });
      try {
        await page.getByText('Teto global vigente: 1500 BinCoins.', { exact: true }).waitFor();
        await page.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
        const dialog = await fillProduct(page, 'Novo produto real', 1500);
        await dialog.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
        await page.getByText('Produto cadastrado.', { exact: true }).waitFor();
        const created = fixture.products.find((p) => p.name === 'Novo produto real');
        assert.equal(created.stock_qty, null);
        assert.equal(created.category, 'Material escolar');
        assert.equal(created.cost_points, 1500);
        assert.match(created.reward_id, /^[0-9a-f-]{36}$/);
        await page
          .locator('app-entity-row')
          .filter({ hasText: 'Novo produto real' })
          .getByRole('button', { name: 'Editar' })
          .click();
        await dialog.getByLabel('Preço em BinCoins').fill('1400');
        await dialog.getByLabel('Estoque', { exact: true }).fill('0');
        await dialog.getByLabel('Disponibilidade').selectOption('false');
        await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
        await page.getByText('Produto atualizado.', { exact: true }).waitFor();
        assert.equal(created.cost_points, 1400);
        assert.equal(created.stock_qty, 0);
        assert.equal(created.is_active, false);
        assert.equal(fixture.redemptions[0].cost_points_snapshot, 1000);
        assert.ok(
          fixture.calls.filter((c) => c.path.endsWith('get_admin_binbazar_products_v1')).length >=
            3,
        );
        assert.equal(
          fixture.calls.some(
            (c) => 'p_school_id' in (c.body || {}) || 'p_admin_id' in (c.body || {}),
          ),
          false,
        );
      } finally {
        await page.close();
      }
    },
  );
}
test('historical price above reduced cap allows other edits but rejects changed price above cap', async () => {
  const { page, fixture } = await open('ADMIN_B', { priceCap: 1000 });
  try {
    await page.getByRole('button', { name: 'Editar', exact: true }).first().click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Produto', { exact: true }).fill('Historical RPC');
    await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
    await page.getByText('Produto atualizado.', { exact: true }).waitFor();
    assert.equal(fixture.products[0].cost_points, 1200);
    await page.getByRole('button', { name: 'Editar', exact: true }).first().click();
    await dialog.getByLabel('Preço em BinCoins').fill('1100');
    await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
    await page
      .getByRole('alert')
      .getByText('Preço acima do teto global vigente.', { exact: true })
      .waitFor();
    assert.equal(fixture.products[0].cost_points, 1200);
    await dialog.getByLabel('Preço em BinCoins').fill('1000');
    await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
    await page.getByText('Produto atualizado.', { exact: true }).waitFor();
    assert.equal(fixture.products[0].cost_points, 1000);
  } finally {
    await page.close();
  }
});
test('backend cap changed during creation rejects stale price and refetches authoritative cap', async () => {
  const { page, fixture } = await open('ADMIN_C', { priceCap: 1500 });
  try {
    await page.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
    const dialog = await fillProduct(page, 'Stale cap product', 1200);
    fixture.priceCap = 1000;
    await dialog.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
    await page
      .getByRole('alert')
      .getByText('Preço acima do teto global vigente.', { exact: true })
      .waitFor();
    await page.getByText('Teto global vigente: 1000 BinCoins.', { exact: true }).waitFor();
    assert.equal(fixture.products.length, 2);
    await dialog.getByLabel('Preço em BinCoins').fill('1000');
    await dialog.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
    await page.getByText('Produto cadastrado.', { exact: true }).waitFor();
    assert.equal(fixture.products.length, 3);
  } finally {
    await page.close();
  }
});
test('lost creation response reuses same UUID/payload and never duplicates product', async () => {
  const { page, fixture } = await open('ADMIN_B', {
    priceCap: 1500,
    loseProductCreateResponse: true,
  });
  try {
    await page.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
    const dialog = await fillProduct(page, 'Idempotent browser product', 1200);
    await dialog.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
    await page
      .getByRole('alert')
      .getByText(/Não foi possível concluir/)
      .waitFor();
    assert.equal(fixture.products.length, 3);
    await dialog.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
    await page.getByText('Produto cadastrado.', { exact: true }).waitFor();
    const calls = fixture.calls.filter((c) => c.path.endsWith('create_admin_binbazar_product_v1'));
    assert.equal(calls.length, 2);
    assert.deepEqual(calls[0].body, calls[1].body);
    assert.equal(fixture.products.length, 3);
  } finally {
    await page.close();
  }
});
test('cap read failure blocks only creation/price; real product edits remain available', async () => {
  const { page, fixture } = await open('ADMIN_C', { capError: true });
  try {
    await page.getByText(/Não foi possível consultar o teto/).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Cadastrar produto' }).isDisabled(), true);
    await page.getByRole('button', { name: 'Editar', exact: true }).first().click();
    const dialog = page.getByRole('dialog');
    assert.equal(await dialog.getByLabel('Preço em BinCoins').isDisabled(), true);
    await dialog.getByLabel('Produto', { exact: true }).fill('Safe edit after cap error');
    await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
    await page.getByText('Produto atualizado.', { exact: true }).waitFor();
    assert.equal(fixture.products[0].cost_points, 1200);
    assert.equal(await page.getByText('Suco natural', { exact: true }).count(), 0);
  } finally {
    await page.close();
  }
});
