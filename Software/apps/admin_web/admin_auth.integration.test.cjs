const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { randomUUID, randomBytes } = require('node:crypto');
const { createClient } = require('@supabase/supabase-js');
const { chromium } = require('playwright');

const enabled = process.env.BINGO_ADMIN_INTEGRATION === '1';
const root = path.resolve(__dirname, '../..');

function localSql(sql) {
  return execFileSync(
    'docker',
    [
      'exec',
      '-i',
      'supabase_db_Software',
      'psql',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-v',
      'ON_ERROR_STOP=1',
      '-At',
    ],
    {
      input: sql,
      encoding: 'utf8',
      windowsHide: true,
    },
  ).trim();
}

test(
  'real local Supabase Auth → own RPC → Angular, restoration, inactive/unlinked and RLS',
  { skip: !enabled },
  async () => {
    // Configuracao obtida exclusivamente do CLI LOCAL; nao aceita URLs/chaves remotas via env.
    const config = JSON.parse(
      execFileSync(
        process.execPath,
        [path.join(root, 'node_modules/supabase/dist/supabase.js'), 'status', '-o', 'json'],
        {
          cwd: root,
          encoding: 'utf8',
          windowsHide: true,
          stdio: ['ignore', 'pipe', 'pipe'],
        },
      ),
    );
    assert.ok(['localhost', '127.0.0.1'].includes(new URL(config.API_URL).hostname));
    const browserUrl = process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/';
    assert.ok(['localhost', '127.0.0.1'].includes(new URL(browserUrl).hostname));
    const options = {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    };
    // Chave tecnica somente neste processo de fixture local, nunca entregue ao browser.
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options);
    const createdUsers = [];
    const adminId = randomUUID();
    const suffix = randomUUID();
    const password = randomBytes(24).toString('base64url');
    let browser;
    try {
      for (const label of ['active', 'unlinked']) {
        const email = `admin-${label}-${suffix}@example.test`;
        const { data, error } = await provisioner.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
        });
        assert.equal(error, null);
        createdUsers.push(data.user);
      }
      localSql(
        `insert into public.admins(id,name,email,role,auth_user_id) values ('${adminId}','Admin Auth Local','${createdUsers[0].email}','ADMIN_A','${createdUsers[0].id}');`,
      );
      const client = createClient(config.API_URL, config.ANON_KEY, options);
      const login = await client.auth.signInWithPassword({
        email: createdUsers[0].email,
        password,
      });
      assert.equal(login.error, null);
      const context = await client.rpc('get_my_admin_context_v1');
      assert.equal(context.error, null);
      assert.equal(context.data.length, 1);
      assert.deepEqual(context.data[0], {
        id: adminId,
        name: 'Admin Auth Local',
        email: createdUsers[0].email,
        role: 'ADMIN_A',
        school_id: null,
        status: 'ACTIVE',
      });
      const select = await client.from('admins').select('*');
      assert.equal(select.error?.code, '42501');
      const write = await client.from('admins').update({ role: 'ADMIN_A' }).eq('id', adminId);
      assert.equal(write.error?.code, '42501');
      const chooseOther = await client.rpc('get_my_admin_context_v1', { admin_id: randomUUID() });
      assert.ok(chooseOther.error);
      const anon = createClient(config.API_URL, config.ANON_KEY, options);
      assert.ok((await anon.rpc('get_my_admin_context_v1')).error);

      browser = await chromium.launch({
        headless: true,
        executablePath:
          process.env.BINGO_BROWSER_PATH ||
          'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
      });
      const page = await browser.newPage();
      await page.route('**/supabase-config.json', (route) =>
        route.fulfill({
          json: {
            SUPABASE_URL: config.API_URL,
            SUPABASE_PUBLISHABLE_KEY: config.ANON_KEY,
          },
        }),
      );
      const rpcRequests = [];
      page.on('request', (request) => {
        if (request.url().includes('/rest/v1/rpc/')) rpcRequests.push(request.postDataJSON());
      });
      const loginUi = async (email) => {
        await page.getByLabel('E-mail institucional').fill(email);
        await page.getByLabel('Senha', { exact: true }).fill(password);
        await page.getByRole('button', { name: 'Acessar o Admin' }).click();
      };
      await page.goto(browserUrl);
      await page.getByLabel('E-mail institucional').fill(createdUsers[0].email);
      await page.getByLabel('Senha', { exact: true }).fill(`${password}-invalid`);
      await page.getByRole('button', { name: 'Acessar o Admin' }).click();
      await page.getByRole('alert').getByText('E-mail ou senha inválidos.').waitFor();
      assert.equal(await page.locator('app-admin-shell').count(), 0);
      await loginUi(createdUsers[0].email);
      await page.locator('app-admin-a').waitFor();
      assert.equal(await page.getByText('Admin Auth Local', { exact: true }).count(), 1);
      await page.reload();
      await page.locator('app-admin-a').waitFor();
      assert.equal(rpcRequests.length, 2);
      assert.deepEqual(rpcRequests, [{}, {}]);

      localSql(`update public.admins set status='INACTIVE' where id='${adminId}';`);
      await page.reload();
      await page
        .getByRole('alert')
        .getByText(/administrativa está inativa/)
        .waitFor();
      assert.equal(await page.locator('app-admin-shell').count(), 0);
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await loginUi(createdUsers[1].email);
      await page
        .getByRole('alert')
        .getByText(/não possui acesso administrativo/)
        .waitFor();
      assert.equal(await page.locator('app-admin-shell').count(), 0);
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await page.getByLabel('Senha').waitFor();
      assert.equal(await page.evaluate(() => localStorage.getItem('bingo.admin.auth')), null);
      await client.auth.signOut({ scope: 'local' });
    } finally {
      await browser?.close();
      localSql(`delete from public.admins where id='${adminId}';`);
      for (const user of createdUsers.reverse()) {
        const { error } = await provisioner.auth.admin.deleteUser(user.id);
        assert.equal(error, null);
      }
    }
  },
);
