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
  'local real Auth B/C, products and redemption delivery/refund through Angular',
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
      assert.ok(['127.0.0.1', 'localhost'].includes(new URL(url).hostname));
    const options = {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    };
    // Technical key stays solely in this ephemeral local fixture process.
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options);
    const users = [],
      clients = [];
    const [school, cls, student, reward, adminB, adminC] = Array.from({ length: 6 }, () =>
      randomUUID(),
    );
    const password = randomBytes(24).toString('base64url');
    let browser;
    async function invoke(client, name, args) {
      const r = await client.rpc(name, args);
      assert.equal(r.error, null);
      return r.data;
    }
    try {
      for (const label of ['B', 'C', 'Student']) {
        const created = await provisioner.auth.admin.createUser({
          email: `bazaar-${label}-${school}@example.test`,
          password,
          email_confirm: true,
        });
        assert.equal(created.error, null);
        users.push(created.data.user);
        const client = createClient(config.API_URL, config.ANON_KEY, options);
        assert.equal(
          (await client.auth.signInWithPassword({ email: created.data.user.email, password }))
            .error,
          null,
        );
        clients.push(client);
      }
      sql(`insert into schools(id,name) values('${school}','Bazaar smoke');
  insert into classes(id,school_id,name,segment,grade) values('${cls}','${school}','Class smoke','TEST','1');
  insert into students(id,school_id,class_id,name,registration,auth_user_id,points_student_balance) values('${student}','${school}','${cls}','Student smoke','001','${users[2].id}',2000);
  insert into rewards(id,school_id,name,cost_points,stock_qty) values('${reward}','${school}','Product smoke',200,5);
  insert into admins(id,school_id,name,email,role,auth_user_id) values('${adminB}','${school}','B smoke','${users[0].email}','ADMIN_B','${users[0].id}'),('${adminC}','${school}','C smoke','${users[1].email}','ADMIN_C','${users[1].id}');`);
      for (const client of clients.slice(0, 2)) {
        assert.equal((await invoke(client, 'get_my_admin_context_v1'))[0].school_id, school);
        assert.equal((await invoke(client, 'get_admin_binbazar_products_v1'))[0].reward_id, reward);
        assert.ok((await client.from('rewards').update({ cost_points: 1 }).eq('id', reward)).error);
        assert.ok(
          (
            await client.rpc('update_admin_binbazar_product_v1', {
              p_reward_id: reward,
              p_name: 'Unsafe',
              p_description: null,
              p_stock_qty: 1,
              p_is_active: true,
              p_cost_points: 1,
            })
          ).error,
        );
      }
      const first = (
        await invoke(clients[2], 'request_redemption_v1', {
          p_request_id: randomUUID(),
          p_reward_id: reward,
        })
      )[0];
      const second = (
        await invoke(clients[2], 'request_redemption_v1', {
          p_request_id: randomUUID(),
          p_reward_id: reward,
        })
      )[0];
      assert.equal(
        sql(`select points_student_balance from students where id='${student}'`),
        '1600',
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
      await page.getByRole('button', { name: 'Produtos e estoque', exact: true }).click();
      await page.getByRole('button', { name: 'Editar', exact: true }).click();
      await page.getByRole('dialog').getByLabel('Produto', { exact: true }).fill('Renamed smoke');
      await page.getByRole('dialog').getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Renamed smoke', { exact: true }).waitFor();
      await page.getByRole('button', { name: /Resgates/ }).click();
      await page.getByLabel('Código ou aluno').fill(first.code);
      await page.getByRole('button', { name: 'Validar entrega' }).click();
      await page.getByRole('dialog').getByRole('button', { name: 'Confirmar entrega' }).click();
      await page.getByText('Resgate entregue.', { exact: true }).waitFor();
      assert.equal(
        sql(`select points_student_balance from students where id='${student}'`),
        '1600',
      );
      assert.equal(sql(`select stock_qty from rewards where id='${reward}'`), '3');
      await invoke(clients[0], 'deliver_admin_redemption_v1', {
        p_redemption_id: first.redemption_id,
      });
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await login(users[1]);
      await page.getByRole('button', { name: /Resgates/ }).click();
      await page.getByLabel('Código ou aluno').fill(second.code);
      await page.getByRole('button', { name: 'Cancelar', exact: true }).click();
      await page.getByRole('dialog').getByRole('button', { name: 'Cancelar resgate' }).click();
      await page.getByText('Resgate cancelado.', { exact: true }).waitFor();
      await invoke(clients[1], 'cancel_admin_redemption_v1', {
        p_redemption_id: second.redemption_id,
      });
      assert.equal(
        sql(`select points_student_balance from students where id='${student}'`),
        '1800',
      );
      assert.equal(sql(`select stock_qty from rewards where id='${reward}'`), '4');
      const rows = await invoke(clients[1], 'get_admin_redemptions_v1');
      assert.deepEqual(rows.map((r) => r.status).sort(), ['CANCELED', 'DELIVERED']);
      assert.ok(
        rows.every(
          (r) => r.reward_name_snapshot === 'Product smoke' && r.cost_points_snapshot === 200,
        ),
      );
      assert.equal(
        sql(`select delivered_by_admin_id from redemptions where id='${first.redemption_id}'`),
        adminB,
      );
      assert.equal(
        sql(
          `select count(*) from audit_logs where school_id='${school}' and action like 'ADMIN_REDEMPTION_%'`,
        ),
        '2',
      );
      assert.equal(
        (
          await clients[1].rpc('deliver_admin_redemption_v1', {
            p_redemption_id: second.redemption_id,
          })
        ).error.code,
        '55000',
      );
      await page.getByRole('button', { name: 'Produtos e estoque', exact: true }).click();
      await page.getByRole('button', { name: 'Editar', exact: true }).click();
      await page.getByRole('dialog').getByLabel('Estoque', { exact: true }).fill('');
      await page.getByRole('dialog').getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Ilimitado', { exact: true }).waitFor();
      assert.equal((await invoke(clients[0], 'get_admin_binbazar_products_v1'))[0].stock_qty, null);
      const third = (
        await invoke(clients[2], 'request_redemption_v1', {
          p_request_id: randomUUID(),
          p_reward_id: reward,
        })
      )[0];
      await invoke(clients[1], 'cancel_admin_redemption_v1', {
        p_redemption_id: third.redemption_id,
      });
      assert.equal(sql(`select stock_qty is null from rewards where id='${reward}'`), 't');
      await page.close();
    } finally {
      await browser?.close();
      sql(
        `delete from audit_logs where school_id='${school}';delete from redemptions where school_id='${school}';delete from rewards where school_id='${school}';delete from students where school_id='${school}';delete from classes where school_id='${school}';delete from admins where school_id='${school}';delete from schools where id='${school}';`,
      );
      for (const client of clients) await client.auth.signOut();
      for (const user of users)
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
