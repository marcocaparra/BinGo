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
async function open(role = 'ADMIN_C', options = {}, view = 'Produtos e estoque') {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, { role, ...options });
  await page.goto(process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/');
  await submitLogin(page);
  await page.getByRole('button', { name: view, exact: view === 'Produtos e estoque' }).click();
  return { page, fixture };
}
for (const role of ['ADMIN_B', 'ADMIN_C']) {
  test(
    role + ' edits real products, unlimited/zero, availability; price and creation blocked',
    async () => {
      const { page, fixture } = await open(role);
      try {
        await page.getByText('Produto RPC', { exact: true }).waitFor();
        assert.equal(await page.getByText('Suco natural', { exact: true }).count(), 0);
        assert.equal(
          await page.getByRole('button', { name: 'Cadastrar produto' }).isDisabled(),
          true,
        );
        assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
        await page.getByRole('button', { name: 'Editar', exact: true }).first().click();
        const dialog = page.getByRole('dialog');
        assert.equal(await dialog.getByRole('spinbutton').count(), 2);
        assert.equal(await dialog.getByLabel('Preço em BinCoins').isDisabled(), true);
        await dialog.getByLabel('Produto', { exact: true }).fill('Produto atualizado RPC');
        await dialog.getByLabel('Descrição').fill('Nova descrição');
        await dialog.getByLabel('Estoque', { exact: true }).fill('0');
        await dialog.getByLabel('Disponibilidade').selectOption('false');
        await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
        await page.getByText('0 unidades', { exact: true }).waitFor();
        assert.equal(fixture.products[0].cost_points, 1200);
        assert.equal(fixture.products[0].is_active, false);
        await page.getByRole('button', { name: 'Editar', exact: true }).first().click();
        await dialog.getByLabel('Estoque', { exact: true }).fill('');
        await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
        await page.getByText('Produto atualizado.', { exact: true }).waitFor();
        assert.equal(fixture.products[0].stock_qty, null);
        assert.equal(fixture.redemptions[0].reward_name_snapshot, 'Snapshot RPC');
      } finally {
        await page.close();
      }
    },
  );
  test(role + ' operates real redemption queue and preserves snapshot display', async () => {
    const { page, fixture } = await open(role, {}, /Resgates/);
    try {
      await page.getByText('BGO-123456789ABC', { exact: true }).waitFor();
      assert.equal(await page.getByText('Snapshot RPC', { exact: true }).count(), 1);
      assert.equal(await page.getByText(/Simulação de resgate|Amanhã|expira/i).count(), 0);
      await page.getByLabel('Código ou aluno').fill('BGO-123');
      await page.getByRole('button', { name: 'Validar entrega' }).click();
      await page.getByRole('dialog').getByRole('button', { name: 'Confirmar entrega' }).click();
      await page.getByText('Resgate entregue.', { exact: true }).waitFor();
      assert.equal(fixture.redemptions[0].status, 'DELIVERED');
      await page.getByRole('button', { name: 'Entregues', exact: true }).click();
      await page.getByText('BGO-123456789ABC', { exact: true }).waitFor();
      assert.ok(
        fixture.calls.filter((c) => c.path.endsWith('get_admin_redemptions_v1')).length >= 2,
      );
    } finally {
      await page.close();
    }
  });
}
test('B pending block is real and cancellation refetches', async () => {
  const { page, fixture } = await open('ADMIN_B', {}, /Pendências/);
  try {
    await page.locator('app-redemptions').getByText('Snapshot RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
    await page
      .locator('app-redemptions')
      .getByRole('button', { name: 'Cancelar', exact: true })
      .click();
    await page.getByRole('dialog').getByRole('button', { name: 'Cancelar resgate' }).click();
    await page.getByText('Resgate cancelado.', { exact: true }).waitFor();
    assert.equal(fixture.redemptions[0].status, 'CANCELED');
    assert.ok(fixture.calls.some((c) => c.path.endsWith('get_admin_binbazar_products_v1')));
  } finally {
    await page.close();
  }
});
for (const domain of ['products', 'redemptions']) {
  test(domain + ' loading, empty and error never fall back to mocks', async () => {
    let release;
    const wait = new Promise((r) => (release = r));
    const { page, fixture } = await open(
      'ADMIN_C',
      { binbazarWait: wait, [domain]: [] },
      domain === 'products' ? 'Produtos e estoque' : /Resgates/,
    );
    try {
      await page
        .getByText(domain === 'products' ? 'Carregando produtos' : 'Carregando resgates', {
          exact: true,
        })
        .waitFor();
      release();
      await page
        .getByText(domain === 'products' ? 'Nenhum produto' : 'Nenhum resgate', { exact: true })
        .waitFor();
      fixture.binbazarError = true;
      await page.getByRole('button', { name: 'Descartes', exact: true }).click();
      await page
        .getByRole('button', {
          name: domain === 'products' ? 'Produtos e estoque' : /Resgates/,
          exact: domain === 'products',
        })
        .click();
      await page
        .getByText(
          domain === 'products'
            ? 'Não foi possível carregar produtos'
            : 'Não foi possível carregar resgates',
          { exact: true },
        )
        .waitFor();
      assert.equal(await page.getByText(/Suco natural|B7K4-92/).count(), 0);
      fixture.binbazarError = false;
      await page.getByRole('button', { name: 'Tentar novamente' }).click();
      await page
        .getByText(domain === 'products' ? 'Nenhum produto' : 'Nenhum resgate', { exact: true })
        .waitFor();
    } finally {
      release();
      await page.close();
    }
  });
}
test('submitting and terminal conflict prevent duplicate actions', async () => {
  let release;
  const wait = new Promise((r) => (release = r));
  const { page, fixture } = await open(
    'ADMIN_C',
    { binbazarMutationWait: wait, binbazarMutationError: '55000' },
    /Resgates/,
  );
  try {
    await page.getByRole('button', { name: 'Validar entrega' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Confirmar entrega' }).click();
    await page.getByRole('button', { name: 'Processando…' }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Processando…' }).isDisabled(), true);
    fixture.redemptions[0].status = 'CANCELED';
    release();
    await page
      .getByRole('alert')
      .getByText(/Conflito/)
      .waitFor();
    assert.equal(
      fixture.calls.filter((c) => c.path.endsWith('deliver_admin_redemption_v1')).length,
      1,
    );
  } finally {
    release();
    await page.close();
  }
});
test('network mutation error keeps operation available for a safe retry', async () => {
  const { page, fixture } = await open('ADMIN_C', { binbazarMutationError: 'NETWORK' }, /Resgates/);
  try {
    await page.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Cancelar resgate' }).click();
    await page
      .getByRole('alert')
      .getByText(/Não foi possível concluir/)
      .waitFor();
    assert.equal(fixture.redemptions[0].status, 'PENDING');
    fixture.binbazarMutationError = null;
    await page.getByRole('dialog').getByRole('button', { name: 'Cancelar resgate' }).click();
    await page.getByText('Resgate cancelado.', { exact: true }).waitFor();
  } finally {
    await page.close();
  }
});
