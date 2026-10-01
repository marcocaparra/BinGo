const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { randomUUID, randomBytes } = require('node:crypto');
const { createClient } = require('@supabase/supabase-js');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
function sql(input) {
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
    { input, encoding: 'utf8', windowsHide: true },
  ).trim();
}
test(
  'real local Auth A creates school/unlinked identities; B manages only local C; C denied',
  { skip: process.env.BINGO_ADMIN_INTEGRATION !== '1' },
  async () => {
    const config = JSON.parse(
      execFileSync(
        process.execPath,
        [path.join(root, 'node_modules/supabase/dist/supabase.js'), 'status', '-o', 'json'],
        { cwd: root, encoding: 'utf8', windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
      ),
    );
    const browserUrl = process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/';
    for (const url of [config.API_URL, browserUrl])
      assert.ok(['localhost', '127.0.0.1'].includes(new URL(url).hostname));
    const options = {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    };
    // Trusted, ephemeral LOCAL fixture provisioning only. Browser receives ANON_KEY.
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options);
    const [school, A, B, C, secondA] = Array.from({ length: 5 }, () => randomUUID());
    const password = randomBytes(24).toString('base64url');
    const users = [],
      clients = [];
    let browser, createdSchool;
    async function rpc(client, name, args) {
      const result = await client.rpc(name, args);
      assert.equal(result.error, null, `${name}: ${result.error?.message}`);
      return result.data;
    }
    try {
      for (const role of ['A', 'B', 'C']) {
        const r = await provisioner.auth.admin.createUser({
          email: `structure-${role}-${school}@example.test`,
          password,
          email_confirm: true,
        });
        assert.equal(r.error, null);
        users.push(r.data.user);
        const client = createClient(config.API_URL, config.ANON_KEY, options);
        assert.equal(
          (await client.auth.signInWithPassword({ email: r.data.user.email, password })).error,
          null,
        );
        clients.push(client);
      }
      sql(`insert into schools(id,name) values('${school}','Scope structure');
      insert into admins(id,school_id,name,email,role,auth_user_id) values
      ('${A}',null,'A structure','${users[0].email}','ADMIN_A','${users[0].id}'),
      ('${B}','${school}','B structure','${users[1].email}','ADMIN_B','${users[1].id}'),
      ('${C}','${school}','C structure','${users[2].email}','ADMIN_C','${users[2].id}');`);
      assert.equal(
        (
          await clients[0].rpc('update_managed_admin_v1', {
            p_admin_id: A,
            p_name: 'A structure',
            p_email: users[0].email,
            p_status: 'INACTIVE',
          })
        ).error.message,
        'MANAGED_ADMIN_LAST_ACTIVE_A',
      );
      browser = await chromium.launch({
        headless: true,
        executablePath:
          process.env.BINGO_BROWSER_PATH ||
          'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
      });
      const page = await browser.newPage();
      await page.route('**/supabase-config.json', (route) =>
        route.fulfill({
          json: { SUPABASE_URL: config.API_URL, SUPABASE_PUBLISHABLE_KEY: config.ANON_KEY },
        }),
      );
      await page.goto(browserUrl);
      async function login(user) {
        await page.getByLabel('E-mail institucional', { exact: true }).fill(user.email);
        await page.getByLabel('Senha', { exact: true }).fill(password);
        await page.getByRole('button', { name: 'Acessar o Admin', exact: true }).click();
        await page.locator('.admin-shell').waitFor();
      }
      await login(users[0]);
      await page.getByRole('button', { name: 'Escolas', exact: true }).click();
      await page.getByRole('button', { name: 'Cadastrar escola', exact: true }).click();
      const d = page.getByRole('dialog');
      await d.getByLabel('Nome da escola').fill('New school ' + school);
      assert.equal(await d.getByLabel('Cidade e estado').count(), 0);
      await d.getByRole('button', { name: 'Cadastrar escola', exact: true }).click();
      await page.getByText('Escola cadastrada.', { exact: true }).waitFor();
      createdSchool = (await rpc(clients[0], 'get_admin_schools_v1')).find(
        (s) => s.name === 'New school ' + school,
      ).school_id;
      assert.equal(
        await rpc(clients[0], 'create_admin_school_v1', {
          p_school_id: createdSchool,
          p_name: 'New school ' + school,
        }),
        createdSchool,
      );
      await page.getByRole('button', { name: 'Administradores', exact: true }).click();
      await page.getByRole('button', { name: 'Cadastrar administrador', exact: true }).click();
      await d.getByLabel('Nome completo').fill('Domain C smoke');
      await d.getByLabel('E-mail institucional').fill(`unlinked-${school}@example.test`);
      await d.getByLabel('Perfil').selectOption('ADMIN_C');
      await d.getByLabel('Escola', { exact: true }).selectOption(school);
      await d.getByRole('button', { name: 'Cadastrar administrador', exact: true }).click();
      await page
        .getByText('Identidade administrativa cadastrada. O acesso ainda precisa ser vinculado.', {
          exact: true,
        })
        .waitFor();
      const identity = (await rpc(clients[0], 'get_managed_admins_v1')).find(
        (a) => a.name === 'Domain C smoke',
      );
      assert.equal(identity.access_linked, false);
      assert.equal('auth_user_id' in identity, false);
      assert.equal(
        sql(
          `select auth_user_id is null and password_hash is null from admins where id='${identity.admin_id}'`,
        ),
        't',
      );
      assert.equal(
        sql(`select count(*) from auth.users where email='unlinked-${school}@example.test'`),
        '0',
      );
      await page
        .locator('app-entity-row')
        .filter({ hasText: 'Domain C smoke' })
        .getByRole('button', { name: 'Gerenciar' })
        .click();
      await d.getByLabel('Estado da conta').selectOption('INACTIVE');
      await d.getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Administrador atualizado.', { exact: true }).waitFor();
      const args = {
        p_admin_id: identity.admin_id,
        p_name: identity.name,
        p_email: identity.email,
        p_status: 'INACTIVE',
      };
      await rpc(clients[0], 'update_managed_admin_v1', args);
      assert.equal(
        sql(
          `select count(*) from audit_logs where action='MANAGED_ADMIN_UPDATED_V1' and metadata->>'admin_id'='${identity.admin_id}'`,
        ),
        '1',
      );
      await rpc(clients[0], 'create_managed_admin_v1', {
        p_admin_id: secondA,
        p_name: 'Unlinked A',
        p_email: `second-${school}@example.test`,
        p_role: 'ADMIN_A',
        p_school_id: null,
        p_status: 'ACTIVE',
      });
      assert.equal(
        (
          await clients[0].rpc('update_managed_admin_v1', {
            p_admin_id: A,
            p_name: 'A structure',
            p_email: users[0].email,
            p_status: 'INACTIVE',
          })
        ).error.message,
        'MANAGED_ADMIN_SELF_DEACTIVATION',
      );
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await login(users[1]);
      await page.getByRole('button', { name: 'Administradores', exact: true }).click();
      await page.getByText('Domain C smoke', { exact: true }).waitFor();
      assert.equal(await page.getByText('A structure', { exact: true }).count(), 0);
      await page
        .locator('app-entity-row')
        .filter({ hasText: 'Domain C smoke' })
        .getByRole('button', { name: 'Gerenciar' })
        .click();
      assert.equal(await d.getByLabel('Perfil').count(), 0);
      await d.getByLabel('Nome completo').fill('C reactivated by B');
      await d.getByLabel('Estado da conta').selectOption('ACTIVE');
      await d.getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Administrador atualizado.', { exact: true }).waitFor();
      assert.equal(sql(`select status from admins where id='${identity.admin_id}'`), 'ACTIVE');
      assert.equal((await clients[1].rpc('get_admin_schools_v1')).error.code, '42501');
      assert.equal(
        (await clients[1].rpc('update_managed_admin_v1', { ...args, p_admin_id: secondA })).error
          .code,
        '42501',
      );
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await login(users[2]);
      assert.equal(
        await page.getByRole('button', { name: 'Administradores', exact: true }).count(),
        0,
      );
      assert.equal((await clients[2].rpc('get_managed_admins_v1')).error.code, '42501');
      for (const client of clients) assert.ok((await client.from('admins').select('*')).error);
      assert.equal(
        sql(
          `select count(*) from audit_logs where actor_id='${A}' and action='MANAGED_ADMIN_CREATED_V1' and school_id is null`,
        ),
        '1',
      );
      await page.close();
    } finally {
      await browser?.close();
      const created = sql(
        `select coalesce(string_agg(quote_literal(entity_id::text),','),'NULL') from admin_structure_creation_receipts where entity_kind='ADMIN' and created_by_admin_id in ('${A}','${B}')`,
      );
      sql(`delete from admin_structure_creation_receipts where created_by_admin_id in ('${A}','${B}');
      delete from audit_logs where actor_id in ('${A}','${B}') or school_id='${school}';
      delete from admins where id in (${created},'${A}','${B}','${C}');
      delete from schools where id in ('${school}',${createdSchool ? `'${createdSchool}'` : 'NULL'});`);
      for (const client of clients) await client.auth.signOut();
      for (const user of users)
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
