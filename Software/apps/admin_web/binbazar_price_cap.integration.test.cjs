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
  'local Auth A configures cap; B/C create/edit through Angular; reduction preserves Mobile snapshots',
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
    // Privileged credentials are fetched only for ephemeral LOCAL provisioning, never sent to Angular.
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options);
    const users = [],
      clients = [];
    const [school, cls, student, adminA, adminB, adminC] = Array.from({ length: 6 }, () =>
      randomUUID(),
    );
    const password = randomBytes(24).toString('base64url');
    const original = JSON.parse(sql('select to_jsonb(s) from global_economic_settings s where id'));
    let browser;
    async function invoke(client, name, args) {
      const r = await client.rpc(name, args);
      assert.equal(r.error, null, `${name}: ${r.error?.message}`);
      return r.data;
    }
    try {
      sql('update global_economic_settings set binbazar_max_price=null where id');
      for (const label of ['A', 'B', 'C', 'Student']) {
        const created = await provisioner.auth.admin.createUser({
          email: `cap-${label}-${school}@example.test`,
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
      sql(`insert into schools(id,name) values('${school}','Cap smoke');
        insert into classes(id,school_id,name,segment,grade) values('${cls}','${school}','Class cap','TEST','1');
        insert into students(id,school_id,class_id,name,auth_user_id,points_student_balance)
          values('${student}','${school}','${cls}','Student cap','${users[3].id}',5000);
        insert into admins(id,school_id,name,email,role,auth_user_id) values
          ('${adminA}',null,'A cap','${users[0].email}','ADMIN_A','${users[0].id}'),
          ('${adminB}','${school}','B cap','${users[1].email}','ADMIN_B','${users[1].id}'),
          ('${adminC}','${school}','C cap','${users[2].email}','ADMIN_C','${users[2].id}');`);
      for (const client of clients.slice(0, 3))
        assert.deepEqual(await invoke(client, 'get_binbazar_price_cap_v1'), [
          { binbazar_max_price: null },
        ]);
      for (const client of clients.slice(1, 3)) {
        assert.equal(
          (await client.rpc('update_binbazar_price_cap_v1', { p_max_price: 1500 })).error.code,
          '42501',
        );
        assert.ok((await client.from('global_economic_settings').select('*')).error);
      }
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
      await page.getByRole('button', { name: 'Economia', exact: true }).click();
      await page
        .locator('app-binbazar-price-cap')
        .getByText('Ainda não configurado', { exact: true })
        .waitFor();
      await page.getByRole('button', { name: 'Definir teto' }).click();
      await page.getByLabel('Teto máximo em BinCoins').fill('1500');
      await page.getByRole('button', { name: 'Salvar teto' }).click();
      await page
        .locator('app-binbazar-price-cap')
        .getByText('1500 BinCoins', { exact: true })
        .waitFor();
      await invoke(clients[0], 'update_binbazar_price_cap_v1', { p_max_price: 1500 });
      assert.equal(
        sql(`select count(*) from audit_logs where actor_id='${adminA}' and school_id is null`),
        '1',
      );
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await login(users[1]);
      await page.getByRole('button', { name: 'Produtos e estoque', exact: true }).click();
      await page.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
      const dialog = page.getByRole('dialog');
      await dialog.getByLabel('Produto', { exact: true }).fill('Cap product');
      await dialog.getByLabel('Preço em BinCoins').fill('1400');
      await dialog.getByLabel('Categoria').fill('Text category');
      await dialog.getByLabel('Estoque', { exact: true }).fill('5');
      await dialog.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
      await page.getByText('Produto cadastrado.', { exact: true }).waitFor();
      const product = (await invoke(clients[1], 'get_admin_binbazar_products_v1'))[0];
      assert.equal(product.name, 'Cap product');
      assert.equal(product.cost_points, 1400);
      const replay = {
        p_reward_id: product.reward_id,
        p_name: product.name,
        p_description: null,
        p_category: 'Text category',
        p_cost_points: 1400,
        p_stock_qty: 5,
        p_is_active: true,
      };
      assert.equal(
        await invoke(clients[1], 'create_admin_binbazar_product_v1', replay),
        product.reward_id,
      );
      const redemption = (
        await invoke(clients[3], 'request_redemption_v1', {
          p_request_id: randomUUID(),
          p_reward_id: product.reward_id,
        })
      )[0];
      const snapshot = sql(
        `select to_jsonb(r) from redemptions r where id='${redemption.redemption_id}'`,
      );
      await invoke(clients[0], 'update_binbazar_price_cap_v1', { p_max_price: 1000 });
      assert.equal(
        sql(
          `select cost_points||':'||stock_qty||':'||is_active from rewards where id='${product.reward_id}'`,
        ),
        '1400:4:true',
      );
      await page.getByRole('button', { name: 'Editar', exact: true }).click();
      await dialog.getByLabel('Produto', { exact: true }).fill('Historical above cap');
      // Actual row has four units after the student's request; don't overwrite reserved stock.
      await dialog.getByLabel('Estoque', { exact: true }).fill('4');
      await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Produto atualizado.', { exact: true }).waitFor();
      await page.getByRole('button', { name: 'Editar', exact: true }).click();
      await dialog.getByLabel('Preço em BinCoins').fill('1300');
      await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
      await page
        .getByRole('alert')
        .getByText('Preço acima do teto global vigente.', { exact: true })
        .waitFor();
      await dialog.getByLabel('Preço em BinCoins').fill('1000');
      await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Produto atualizado.', { exact: true }).waitFor();
      assert.equal(
        sql(`select to_jsonb(r) from redemptions r where id='${redemption.redemption_id}'`),
        snapshot,
      );
      assert.equal(
        sql(`select points_student_balance from students where id='${student}'`),
        '3600',
      );
      assert.equal(
        await invoke(clients[1], 'create_admin_binbazar_product_v1', replay),
        product.reward_id,
      );
      assert.equal(
        sql(
          `select count(*) from audit_logs where action='ADMIN_PRODUCT_CREATED_V1' and school_id='${school}'`,
        ),
        '1',
      );
      const updates = sql(
        `select count(*) from audit_logs where action='ADMIN_PRODUCT_UPDATED_V1' and school_id='${school}'`,
      );
      await invoke(clients[1], 'update_admin_binbazar_product_v1', {
        p_reward_id: product.reward_id,
        p_name: 'Historical above cap',
        p_description: null,
        p_category: 'Text category',
        p_cost_points: 1000,
        p_stock_qty: 4,
        p_is_active: true,
      });
      assert.equal(
        sql(
          `select count(*) from audit_logs where action='ADMIN_PRODUCT_UPDATED_V1' and school_id='${school}'`,
        ),
        updates,
      );
      await invoke(clients[3], 'cancel_my_redemption_v1', {
        p_redemption_id: redemption.redemption_id,
      });
      assert.equal(
        sql(`select points_student_balance from students where id='${student}'`),
        '5000',
      );
      assert.equal(sql(`select stock_qty from rewards where id='${product.reward_id}'`), '5');
      assert.equal(
        sql(`select cost_points_snapshot from redemptions where id='${redemption.redemption_id}'`),
        '1400',
      );
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await login(users[2]);
      await page.getByRole('button', { name: 'Produtos e estoque', exact: true }).click();
      await page.getByText('Teto global vigente: 1000 BinCoins.', { exact: true }).waitFor();
      await page.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
      await dialog.getByLabel('Produto', { exact: true }).fill('C unlimited product');
      await dialog.getByLabel('Preço em BinCoins').fill('1000');
      await dialog.getByRole('button', { name: 'Cadastrar produto', exact: true }).click();
      await page.getByText('Produto cadastrado.', { exact: true }).waitFor();
      const rows = await invoke(clients[2], 'get_admin_binbazar_products_v1');
      assert.equal(rows.find((p) => p.name === 'C unlimited product').stock_qty, null);
      assert.equal(rows.length, 2);
      await page.close();
    } finally {
      await browser?.close();
      sql(`delete from audit_logs where school_id='${school}' or actor_id='${adminA}';
        delete from redemptions where school_id='${school}';delete from rewards where school_id='${school}';
        delete from students where school_id='${school}';delete from classes where school_id='${school}';
        delete from admins where id in ('${adminA}','${adminB}','${adminC}');delete from schools where id='${school}';
        update global_economic_settings set binbazar_max_price=${original.binbazar_max_price ?? 'null'},
          created_at='${original.created_at}',updated_at='${original.updated_at}' where id;`);
      for (const client of clients) await client.auth.signOut();
      for (const user of users)
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
