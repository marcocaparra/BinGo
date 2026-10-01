const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { randomUUID, randomBytes } = require('node:crypto');
const { createClient } = require('@supabase/supabase-js');
const { chromium } = require('playwright');
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
  'local real Auth/RPC/Angular machines: A global, B/C scoped, inactive/unlinked denied',
  { skip: process.env.BINGO_ADMIN_INTEGRATION !== '1' },
  async () => {
    const root = path.resolve(__dirname, '../..');
    const config = JSON.parse(
      execFileSync(
        process.execPath,
        [path.join(root, 'node_modules/supabase/dist/supabase.js'), 'status', '-o', 'json'],
        { cwd: root, encoding: 'utf8', windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
      ),
    );
    const url = process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/';
    for (const u of [config.API_URL, url])
      assert.ok(['127.0.0.1', 'localhost'].includes(new URL(u).hostname));
    const opts = { auth: { persistSession: false, autoRefreshToken: false } };
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, opts);
    const schools = [randomUUID(), randomUUID()],
      users = [],
      clients = [],
      admins = [],
      machines = [randomUUID(), randomUUID()];
    const password = randomBytes(24).toString('base64url');
    let browser;
    try {
      sql(`insert into schools(id,name) values ('${schools[0]}','Totens local Norte'),('${schools[1]}','Totens local Sul');
      insert into machines(id,school_id,name,status) values ('${machines[0]}','${schools[0]}','Totem local Norte','ONLINE'),('${machines[1]}','${schools[1]}','Totem local Sul','OUT_OF_SERVICE');`);
      for (const [i, role] of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C', 'INACTIVE', 'UNLINKED'].entries()) {
        const r = await provisioner.auth.admin.createUser({
          email: `machines-${i}-${schools[0]}@example.test`,
          password,
          email_confirm: true,
        });
        assert.equal(r.error, null);
        users.push(r.data.user);
        if (role !== 'UNLINKED') {
          const id = randomUUID();
          admins.push(id);
          sql(
            `insert into admins(id,name,email,role,school_id,status,auth_user_id) values ('${id}','Totem admin ${i}','${r.data.user.email}','${role === 'INACTIVE' ? 'ADMIN_C' : role}',${role === 'ADMIN_A' ? 'null' : `'${schools[0]}'`},'${role === 'INACTIVE' ? 'INACTIVE' : 'ACTIVE'}','${r.data.user.id}');`,
          );
        }
        const client = createClient(config.API_URL, config.ANON_KEY, opts);
        assert.equal(
          (await client.auth.signInWithPassword({ email: r.data.user.email, password })).error,
          null,
        );
        clients.push(client);
        const result = await client.rpc('get_admin_machines_v1');
        if (i >= 3) {
          assert.equal(result.error.code, '42501');
          continue;
        }
        assert.equal(result.error, null);
        assert.ok(result.data.some((m) => m.machine_id === machines[0]));
        if (i === 0) assert.ok(result.data.some((m) => m.machine_id === machines[1]));
        else assert.ok(result.data.every((m) => m.school_id === schools[0]));
        assert.ok(result.data.every((m) => !('api_key_hash' in m)));
        assert.ok((await client.from('machines').select('name')).error);
      }
      const anon = createClient(config.API_URL, config.ANON_KEY, opts);
      assert.equal((await anon.rpc('get_admin_machines_v1')).error.code, '42501');
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
      await page.goto(url);
      for (let i = 0; i < 3; i++) {
        await page.getByLabel('E-mail institucional', { exact: true }).fill(users[i].email);
        await page.getByLabel('Senha', { exact: true }).fill(password);
        await page.getByRole('button', { name: 'Acessar o Admin', exact: true }).click();
        await page.getByRole('button', { name: 'Totens', exact: true }).click();
        await page.getByText('Totem local Norte', { exact: true }).waitFor();
        assert.equal(
          await page.getByText('Totem local Sul', { exact: true }).count(),
          i === 0 ? 1 : 0,
        );
        await page
          .locator('.machine-card')
          .filter({ hasText: 'Totem local Norte' })
          .getByText('Não registrada', { exact: true })
          .waitFor();
        await page.getByRole('button', { name: 'Atualizar Totens', exact: true }).click();
        await page.getByText('Totem local Norte', { exact: true }).waitFor();
        await page.getByRole('button', { name: 'Sair', exact: true }).click();
        await page.getByRole('button', { name: 'Acessar o Admin', exact: true }).waitFor();
      }
    } finally {
      await browser?.close();
      sql(
        `delete from machines where id in ('${machines.join("','")}'); delete from admins where id in ('${admins.join("','")}'); delete from schools where id in ('${schools.join("','")}');`,
      );
      for (const client of clients) await client.auth.signOut();
      for (const user of users)
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
