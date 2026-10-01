const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { installSupabaseFixture, submitLogin, schoolId } = require('./test/supabase-fixture.cjs');
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
async function open(options = {}) {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, options);
  await page.goto(process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/');
  await submitLogin(page);
  await page.getByRole('button', { name: 'Totens', exact: true }).click();
  return { page, fixture };
}
const rows = ['ONLINE', 'OFFLINE', 'MAINTENANCE', 'OUT_OF_SERVICE'].map((status, i) => ({
  machine_id: 'machine-' + i,
  school_id: i < 2 ? schoolId : '10000000-0000-4000-8000-000000000002',
  school_name: i < 2 ? 'Escola Norte RPC' : 'Escola Sul RPC',
  name: 'Máquina real ' + i,
  status,
  firmware_version: i ? 'v2' : null,
  last_seen: i ? '2026-10-01T10:00:00Z' : null,
  bin_full: i === 1,
  camera_ok: i !== 1,
  net_ok: i !== 0,
}));
for (const role of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C'])
  test(role + ' reads persisted machines and no invented diagnostics', async () => {
    const { page, fixture } = await open({ role, machines: rows });
    try {
      await page.getByText('Máquina real 0', { exact: true }).waitFor();
      assert.equal(await page.locator('.machine-card').count(), role === 'ADMIN_A' ? 4 : 2);
      for (const status of role === 'ADMIN_A' ? rows.map((r) => r.status) : ['ONLINE', 'OFFLINE'])
        await page.getByText(status, { exact: true }).waitFor();
      await page.getByText('Não informado', { exact: true }).waitFor();
      await page.getByText('Não registrada', { exact: true }).waitFor();
      const text = await page.locator('app-machines').innerText();
      for (const old of [
        'BT-',
        'Porta',
        'Depósitos',
        'diagnóstico',
        'Totem Biblioteca',
        'Com problema',
      ])
        assert.ok(!text.includes(old), old);
      assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
      assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
      assert.deepEqual(
        fixture.calls.filter((c) => c.path.endsWith('get_admin_machines_v1')).map((c) => c.body),
        [{}],
      );
      for (const width of [420, 1024]) {
        await page.setViewportSize({ width, height: 800 });
        assert.ok(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
          ),
        );
      }
    } finally {
      await page.close();
    }
  });
test('loading, empty, error and authoritative refetch never fall back to mocks', async () => {
  let release;
  const wait = new Promise((r) => (release = r));
  const { page, fixture } = await open({ machinesWait: wait, machines: [] });
  try {
    await page.getByRole('heading', { name: 'Carregando Totens', exact: true }).waitFor();
    assert.equal(await page.locator('.machine-card').count(), 0);
    release();
    fixture.machinesWait = null;
    await page.getByRole('heading', { name: 'Nenhum Totem', exact: true }).waitFor();
    fixture.machinesError = true;
    await page.getByRole('button', { name: 'Atualizar Totens', exact: true }).click();
    await page
      .getByRole('heading', { name: 'Não foi possível carregar Totens', exact: true })
      .waitFor();
    assert.equal(await page.locator('.machine-card').count(), 0);
    fixture.machinesError = false;
    fixture.machines = rows;
    await page.getByRole('button', { name: 'Tentar novamente', exact: true }).click();
    await page.getByText('Máquina real 0', { exact: true }).waitFor();
    fixture.machines = [{ ...rows[0], name: 'Fotografia atualizada' }];
    await page.getByRole('button', { name: 'Atualizar Totens', exact: true }).click();
    await page.getByText('Fotografia atualizada', { exact: true }).waitFor();
    assert.equal(await page.getByText('Máquina real 0', { exact: true }).count(), 0);
  } finally {
    release();
    await page.close();
  }
});
test('logout/login discards a late response from another role and school', async () => {
  let release;
  const wait = new Promise((r) => (release = r));
  let started;
  const read = new Promise((r) => (started = r));
  const { page, fixture } = await open({
    role: 'ADMIN_A',
    machines: rows,
    machinesWait: wait,
    onMachineRead: started,
  });
  try {
    await read;
    await page.getByRole('button', { name: 'Sair', exact: true }).click();
    await page.getByRole('button', { name: 'Acessar o Admin', exact: true }).waitFor();
    fixture.role = 'ADMIN_C';
    fixture.schoolId = '10000000-0000-4000-8000-000000000002';
    fixture.machinesWait = null;
    await submitLogin(page);
    await page.getByRole('button', { name: 'Totens', exact: true }).click();
    await page.getByText('Máquina real 2', { exact: true }).waitFor();
    const late = page.waitForResponse((r) => r.url().endsWith('/rpc/get_admin_machines_v1'));
    release();
    await late;
    assert.equal(await page.locator('.machine-card').count(), 2);
    assert.equal(await page.getByText('Máquina real 0', { exact: true }).count(), 0);
    await page.getByRole('button', { name: 'Atualizar Totens', exact: true }).click();
    await page.getByText('Máquina real 2', { exact: true }).waitFor();
  } finally {
    release();
    await page.close();
  }
});
