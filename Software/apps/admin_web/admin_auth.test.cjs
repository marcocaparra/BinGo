const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { installSupabaseFixture, submitLogin } = require('./test/supabase-fixture.cjs');

const url = process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/';
const browserOptions = {
  headless: true,
  executablePath:
    process.env.BINGO_BROWSER_PATH ||
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};
let browser;
before(async () => {
  browser = await chromium.launch(browserOptions);
});
after(async () => {
  await browser?.close();
});

async function withPage(options, run) {
  const page = await browser.newPage();
  try {
    const fixture = await installSupabaseFixture(page, options);
    await page.goto(url);
    await run(page, fixture);
  } finally {
    await page.close();
  }
}

test('login has only empty email/password fields and no role selector', () =>
  withPage({}, async (page, fixture) => {
    await page.getByLabel('Senha').waitFor();
    assert.equal(await page.getByLabel('Perfil demonstrativo').count(), 0);
    assert.equal(await page.locator('select').count(), 0);
    assert.equal(await page.getByLabel('Senha').inputValue(), '');
    assert.equal(await page.getByLabel('E-mail institucional').inputValue(), '');
    assert.equal(fixture.calls.length, 0);
    assert.equal(await page.locator('app-admin-shell').count(), 0);
  }));

for (const role of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C']) {
  test(`valid credentials resolve ${role} exclusively through the RPC`, () =>
    withPage({ role }, async (page, fixture) => {
      await submitLogin(page);
      await page.locator(`app-admin-${role.slice(-1).toLowerCase()}`).waitFor();
      assert.equal(await page.getByLabel('Perfil demonstrativo').count(), 0);
      assert.equal(await page.getByText('Administrador Autenticado', { exact: true }).count(), 1);
      assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 1);
      const rpc = fixture.calls.filter((x) => x.path.includes('/rpc/'));
      assert.equal(rpc.length, 1);
      assert.deepEqual(rpc[0].body, {});
      const login = fixture.calls.find((x) => x.path.includes('/token'));
      assert.equal(login.body.email, 'admin@example.test');
      assert.equal(login.body.password, 'test-password');
      assert.ok(!('role' in login.body));
    }));
}

test('invalid credentials stay at login without any admin RPC', () =>
  withPage({ invalidCredentials: true }, async (page, fixture) => {
    await submitLogin(page);
    await page.getByRole('alert').getByText('E-mail ou senha inválidos.').waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
    assert.equal(fixture.calls.filter((x) => x.path.includes('/rpc/')).length, 0);
    assert.equal(await page.getByLabel('Senha').inputValue(), '');
  }));

for (const negative of [
  {
    title: 'Auth without admin',
    options: { linked: false },
    message: /não possui acesso administrativo/,
  },
  {
    title: 'inactive admin',
    options: { status: 'INACTIVE' },
    message: /administrativa está inativa/,
  },
]) {
  test(`${negative.title} blocks all normal views and permits logout`, () =>
    withPage(negative.options, async (page) => {
      await submitLogin(page);
      await page.getByRole('alert').getByText(negative.message).waitFor();
      assert.equal(await page.locator('app-admin-shell').count(), 0);
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await page.getByRole('button', { name: 'Acessar o Admin' }).waitFor();
      await page.reload();
      await page.getByLabel('Senha').waitFor();
      assert.equal(await page.locator('app-admin-shell').count(), 0);
    }));
}

test('refresh uses persisted Supabase session but resolves role and school again', () =>
  withPage({ role: 'ADMIN_A' }, async (page, fixture) => {
    await submitLogin(page);
    await page.locator('app-admin-a').waitFor();
    fixture.role = 'ADMIN_B';
    await page.reload();
    await page.locator('app-admin-b').waitFor();
    assert.equal(fixture.calls.filter((x) => x.path.includes('/token')).length, 1);
    assert.equal(fixture.calls.filter((x) => x.path.includes('/rpc/')).length, 2);
    fixture.status = 'INACTIVE';
    await page.reload();
    await page
      .getByRole('alert')
      .getByText(/administrativa está inativa/)
      .waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
  }));

test('logout clears context and SDK session without requiring refresh', () =>
  withPage({ role: 'ADMIN_A' }, async (page, fixture) => {
    await submitLogin(page);
    await page.locator('app-admin-a').waitFor();
    await page.getByRole('button', { name: 'Sair', exact: true }).click();
    await page.getByLabel('Senha').waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
    assert.equal(await page.evaluate(() => localStorage.getItem('bingo.admin.auth')), null);
    fixture.role = 'ADMIN_C';
    await submitLogin(page);
    await page.locator('app-admin-c').waitFor();
    assert.equal(await page.locator('app-admin-a').count(), 0);
  }));

test('network failure and backend failure never activate demo authentication', () =>
  withPage({ networkError: true }, async (page, fixture) => {
    await submitLogin(page);
    await page
      .getByRole('alert')
      .getByText(/Não foi possível autenticar/)
      .waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
    fixture.networkError = false;
    fixture.rpcError = true;
    await submitLogin(page);
    await page
      .getByRole('alert')
      .getByText(/Não foi possível verificar/)
      .waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
    fixture.rpcError = false;
    await page.getByRole('button', { name: 'Tentar novamente' }).click();
    await page.locator('app-admin-c').waitFor();
  }));

test('URL, manual storage and Auth metadata cannot choose role or school', () =>
  withPage({}, async (page) => {
    await page.evaluate(() => {
      localStorage.setItem('role', 'ADMIN_A');
      localStorage.setItem('school_id', 'other-school');
    });
    await page.goto(`${url}?role=ADMIN_A&school_id=other-school`);
    await submitLogin(page);
    await page.locator('app-admin-c').waitFor();
    assert.equal(await page.locator('app-admin-a').count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Escolas', exact: true }).count(), 0);
    assert.equal(await page.getByLabel('Perfil demonstrativo').count(), 0);
    await page.reload();
    await page.locator('app-admin-c').waitFor();
  }));

for (const options of [
  { role: 'ADMIN' },
  { role: 'ADMIN_B', schoolId: null },
  { status: 'UNKNOWN' },
]) {
  test(`malformed context ${JSON.stringify(options)} fails closed`, () =>
    withPage(options, async (page) => {
      await submitLogin(page);
      await page
        .getByRole('alert')
        .getByText(/Não foi possível verificar/)
        .waitFor();
      assert.equal(await page.locator('app-admin-shell').count(), 0);
    }));
}

test('removing SDK session in another tab promptly removes the shell', () =>
  withPage({}, async (page) => {
    await submitLogin(page);
    await page.locator('app-admin-c').waitFor();
    await page.evaluate(() => {
      const channel = new BroadcastChannel('bingo.admin.auth');
      channel.postMessage({ event: 'SIGNED_OUT', session: null });
      channel.close();
    });
    await page.getByLabel('Senha').waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
  }));

test('refresh-token event resolves context again and blocks newly inactive admin', () =>
  withPage({}, async (page, fixture) => {
    await submitLogin(page);
    await page.locator('app-admin-c').waitFor();
    fixture.status = 'INACTIVE';
    await page.evaluate(() => {
      const session = JSON.parse(localStorage.getItem('bingo.admin.auth'));
      session.access_token += '-refreshed';
      const channel = new BroadcastChannel('bingo.admin.auth');
      channel.postMessage({ event: 'TOKEN_REFRESHED', session });
      channel.close();
    });
    await page
      .getByRole('alert')
      .getByText(/administrativa está inativa/)
      .waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
    assert.equal(fixture.calls.filter((x) => x.path.includes('/rpc/')).length, 2);
  }));

test('pending context response cannot reopen the shell after a sign-out event', () =>
  withPage({}, async (page, fixture) => {
    let release;
    fixture.rpcWait = new Promise((resolve) => {
      release = resolve;
    });
    await submitLogin(page);
    await page.getByRole('status').getByText('Verificando acesso administrativo…').waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
    await page.evaluate(() => {
      const channel = new BroadcastChannel('bingo.admin.auth');
      channel.postMessage({ event: 'SIGNED_OUT', session: null });
      channel.close();
    });
    await page.getByLabel('Senha').waitFor();
    release();
    await page.waitForResponse((response) =>
      response.url().includes('/rpc/get_my_admin_context_v1'),
    );
    // Aguarda renderizacao posterior a conclusao da RPC, sem sleep arbitrario.
    await page.evaluate(
      () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
    );
    assert.equal(await page.locator('app-admin-shell').count(), 0);
  }));

test('failed logout stays blocked and offers a second sign-out attempt', () =>
  withPage({ logoutError: true }, async (page, fixture) => {
    await submitLogin(page);
    await page.locator('app-admin-c').waitFor();
    await page.getByRole('button', { name: 'Sair', exact: true }).click();
    await page
      .getByRole('alert')
      .getByText(/Não foi possível encerrar a sessão/)
      .waitFor();
    assert.equal(await page.locator('app-admin-shell').count(), 0);
    fixture.logoutError = false;
    await page.getByRole('button', { name: 'Sair', exact: true }).click();
    await page.getByLabel('Senha').waitFor();
    assert.equal(await page.evaluate(() => localStorage.getItem('bingo.admin.auth')), null);
  }));
