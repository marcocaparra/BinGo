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
async function open(role, view, options = {}) {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, { role, ...options });
  await page.goto(process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/');
  await submitLogin(page);
  await page.getByRole('button', { name: view, exact: true }).click();
  return { page, fixture };
}
test('A real schools show derived counts and create only name, preserving UUID after lost response', async () => {
  const { page, fixture } = await open('ADMIN_A', 'Escolas', { loseStructureResponse: true });
  try {
    await page.getByText('Escola estrutural RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('Colégio ENIAC', { exact: true }).count(), 0);
    await page.getByText('1 alunos · 2 turmas', { exact: true }).waitFor();
    await page.getByRole('button', { name: 'Cadastrar escola', exact: true }).click();
    const d = page.getByRole('dialog');
    assert.equal(await d.locator('input').count(), 1);
    assert.equal(await d.locator('select').count(), 0);
    await d.getByLabel('Nome da escola').fill('Escola criada RPC');
    await d.getByRole('button', { name: 'Cadastrar escola', exact: true }).click();
    await d
      .getByRole('alert')
      .getByText(/Não foi possível salvar/)
      .waitFor();
    await d.getByRole('button', { name: 'Cadastrar escola', exact: true }).click();
    await page.getByText('Escola cadastrada.', { exact: true }).waitFor();
    assert.equal(fixture.managedSchools.length, 2);
    const calls = fixture.calls.filter((c) => c.path.endsWith('create_admin_school_v1'));
    assert.deepEqual(calls[0].body, calls[1].body);
    assert.deepEqual(Object.keys(calls[0].body).sort(), ['p_school_id', 'p_name'].sort());
    assert.match(calls[0].body.p_school_id, /^[0-9a-f-]{36}$/);
    assert.equal(await page.getByRole('button', { name: 'Abrir', exact: true }).count(), 0);
  } finally {
    await page.close();
  }
});
for (const role of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C']) {
  test('A creates domain identity ' + role + ' without passwords or Auth binding', async () => {
    const { page, fixture } = await open('ADMIN_A', 'Administradores');
    try {
      await page.getByRole('button', { name: 'Cadastrar administrador', exact: true }).click();
      const d = page.getByRole('dialog');
      assert.equal(await d.locator('input[type=password]').count(), 0);
      await d.getByLabel('Nome completo').fill('Identidade ' + role);
      await d.getByLabel('E-mail institucional').fill(role.toLowerCase() + '@example.test');
      await d.getByLabel('Perfil').selectOption(role);
      if (role !== 'ADMIN_A')
        await d.getByLabel('Escola', { exact: true }).selectOption(fixture.schoolId);
      else assert.equal(await d.getByLabel('Escola', { exact: true }).count(), 0);
      await d.getByRole('button', { name: 'Cadastrar administrador', exact: true }).click();
      await page
        .getByText('Identidade administrativa cadastrada. O acesso ainda precisa ser vinculado.', {
          exact: true,
        })
        .waitFor();
      const created = fixture.managedAdmins.find((a) => a.name === 'Identidade ' + role);
      assert.equal(created.role, role);
      assert.equal(created.access_linked, false);
      assert.equal(created.school_id, role === 'ADMIN_A' ? null : fixture.schoolId);
      const row = page.locator('app-entity-row').filter({ hasText: 'Identidade ' + role });
      await row.getByText(role + ' · Sem vínculo de acesso', { exact: true }).waitFor();
      await row.getByRole('button', { name: 'Gerenciar' }).click();
      assert.equal(await d.getByLabel('Perfil').count(), 0);
      assert.equal(await d.getByLabel('Escola', { exact: true }).count(), 0);
      await d.getByLabel('Nome completo').fill('Editada ' + role);
      await d.getByLabel('Estado da conta').selectOption('INACTIVE');
      await d.getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Administrador atualizado.', { exact: true }).waitFor();
      assert.equal(created.status, 'INACTIVE');
      const body = fixture.calls.findLast((c) => c.path.endsWith('update_managed_admin_v1')).body;
      assert.deepEqual(
        Object.keys(body).sort(),
        ['p_admin_id', 'p_name', 'p_email', 'p_status'].sort(),
      );
      assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
    } finally {
      await page.close();
    }
  });
}
test('B only sees C and creates C with backend school scope; updates and reactivates', async () => {
  const { page, fixture } = await open('ADMIN_B', 'Administradores');
  try {
    await page.getByText('C estrutural RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('A estrutural RPC', { exact: true }).count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Escolas', exact: true }).count(), 0);
    await page.getByRole('button', { name: 'Cadastrar Admin C' }).click();
    const d = page.getByRole('dialog');
    assert.equal(await d.getByLabel('Perfil').count(), 0);
    assert.equal(await d.getByLabel('Escola', { exact: true }).count(), 0);
    await d.getByLabel('Nome completo').fill('C criado pelo B');
    await d.getByLabel('E-mail institucional').fill('newc@example.test');
    await d.getByLabel('Estado da conta').selectOption('INACTIVE');
    await d.getByRole('button', { name: 'Cadastrar administrador', exact: true }).click();
    await page.getByText('C criado pelo B', { exact: true }).waitFor();
    const call = fixture.calls.find((c) => c.path.endsWith('create_managed_admin_v1')).body;
    assert.equal(call.p_role, 'ADMIN_C');
    assert.equal(call.p_school_id, null);
    await page
      .locator('app-entity-row')
      .filter({ hasText: 'C criado pelo B' })
      .getByRole('button', { name: 'Gerenciar' })
      .click();
    await d.getByLabel('Estado da conta').selectOption('ACTIVE');
    await d.getByRole('button', { name: 'Salvar alterações' }).click();
    await page.getByText('Administrador atualizado.', { exact: true }).waitFor();
    assert.equal(fixture.managedAdmins.find((a) => a.name === 'C criado pelo B').status, 'ACTIVE');
  } finally {
    await page.close();
  }
});
test('self inactivation unavailable; backend email/last-A conflicts retain dialog and snapshot', async () => {
  const { page, fixture } = await open('ADMIN_A', 'Administradores');
  try {
    await page
      .locator('app-entity-row')
      .filter({ has: page.getByText('A estrutural RPC', { exact: true }) })
      .getByRole('button', { name: 'Gerenciar' })
      .click();
    const d = page.getByRole('dialog');
    assert.equal(await d.locator('option[value=INACTIVE]').isDisabled(), true);
    await d.getByLabel('E-mail institucional').fill('c@example.test');
    await d.getByRole('button', { name: 'Salvar alterações' }).click();
    await d
      .getByRole('alert')
      .getByText('Conflito: e-mail já cadastrado.', { exact: true })
      .waitFor();
    assert.equal(fixture.managedAdmins[0].email, 'a@example.test');
    fixture.structureMutationError = 'MANAGED_ADMIN_LAST_ACTIVE_A';
    await d.getByLabel('E-mail institucional').fill('a@example.test');
    await d.getByRole('button', { name: 'Salvar alterações' }).click();
    await d
      .getByRole('alert')
      .getByText(/preservar pelo menos um ADMIN_A/)
      .waitFor();
    assert.equal(await d.count(), 1);
  } finally {
    await page.close();
  }
});
for (const domain of ['schools', 'admins']) {
  test(domain + ' loading/empty/error/retry have no mock fallback', async () => {
    let release;
    const { page, fixture } = await open(
      'ADMIN_A',
      domain === 'schools' ? 'Escolas' : 'Administradores',
      {
        structureWait: new Promise((r) => (release = r)),
        managedSchools: [],
        managedAdmins: [],
      },
    );
    try {
      const noun = domain === 'schools' ? 'escolas' : 'administradores';
      await page.getByText('Carregando ' + noun, { exact: true }).waitFor();
      release();
      await page
        .getByText(domain === 'schools' ? 'Nenhuma escola' : 'Nenhum administrador', {
          exact: true,
        })
        .waitFor();
      fixture.structureError = true;
      await page.getByRole('button', { name: 'Missões', exact: true }).click();
      await page
        .getByRole('button', {
          name: domain === 'schools' ? 'Escolas' : 'Administradores',
          exact: true,
        })
        .click();
      await page.getByText('Não foi possível carregar ' + noun, { exact: true }).waitFor();
      assert.equal(await page.getByText(/Colégio ENIAC|Paula Mendes|Guarulhos/).count(), 0);
      fixture.structureError = false;
      await page.getByRole('button', { name: 'Tentar novamente' }).click();
      await page
        .getByText(domain === 'schools' ? 'Nenhuma escola' : 'Nenhum administrador', {
          exact: true,
        })
        .waitFor();
    } finally {
      release();
      await page.close();
    }
  });
}
test('structure forms expose submitting and keep layout contained at narrow width', async () => {
  let release;
  const { page } = await open('ADMIN_A', 'Escolas', {
    structureMutationWait: new Promise((r) => (release = r)),
  });
  try {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByRole('button', { name: 'Cadastrar escola' }).click();
    await page.getByLabel('Nome da escola').fill('School responsive');
    await page.getByRole('dialog').getByRole('button', { name: 'Cadastrar escola' }).click();
    await page.getByRole('button', { name: 'Salvando…' }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Salvando…' }).isDisabled(), true);
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    release();
    await page.getByText('Escola cadastrada.', { exact: true }).waitFor();
  } finally {
    release();
    await page.close();
  }
});

for (const role of ['ADMIN_A', 'ADMIN_B']) {
  test(
    role + ' restored active Auth context reloads managed identities when returning to the view',
    async () => {
      const { page, fixture } = await open(role, 'Administradores');
      try {
        await page.getByText('C estrutural RPC', { exact: true }).waitFor();
        fixture.managedAdmins[1].name = 'C após renovação';
        const restored = page.waitForResponse((r) =>
          r.url().endsWith('/rpc/get_my_admin_context_v1'),
        );
        await page.evaluate(() => {
          const session = JSON.parse(localStorage.getItem('bingo.admin.auth'));
          session.access_token += '-refreshed';
          const channel = new BroadcastChannel('bingo.admin.auth');
          channel.postMessage({ event: 'TOKEN_REFRESHED', session });
          channel.close();
        });
        await restored;
        await page.getByRole('button', { name: 'Administradores', exact: true }).click();
        await page.getByText('C após renovação', { exact: true }).waitFor();
        assert.ok(
          fixture.calls.filter((c) => c.path.endsWith('get_managed_admins_v1')).length >= 2,
        );
        assert.equal(
          await page.getByText('Carregando administradores', { exact: true }).count(),
          0,
        );
      } finally {
        await page.close();
      }
    },
  );
}
