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
  'real local Auth A/B/C dashboards equal existing RPC data, honor scope and refresh decisions',
  { skip: process.env.BINGO_ADMIN_INTEGRATION !== '1' },
  async () => {
    const config = JSON.parse(
      execFileSync(
        process.execPath,
        [path.join(root, 'node_modules/supabase/dist/supabase.js'), 'status', '-o', 'json'],
        { cwd: root, encoding: 'utf8', windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
      ),
    );
    const url = process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/';
    for (const target of [config.API_URL, url])
      assert.ok(['127.0.0.1', 'localhost'].includes(new URL(target).hostname));
    const options = {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    };
    // Provisionamento efêmero confiável somente LOCAL. Browser recebe apenas anon.
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options);
    const ids = Array.from({ length: 17 }, () => randomUUID());
    const [
      school,
      otherSchool,
      A,
      B,
      C,
      otherC,
      class1,
      class2,
      foreignClass,
      student,
      inactiveStudent,
      foreignStudent,
      machine,
      product,
      zeroProduct,
      unlimitedProduct,
      foreignProduct,
    ] = ids;
    const password = randomBytes(24).toString('base64url');
    const users = [],
      clients = [];
    let browser;
    const original = sql('select row_to_json(g) from global_economic_settings g');
    async function rpc(client, name, args) {
      const r = await client.rpc(name, args);
      assert.equal(r.error, null, `${name}: ${r.error?.message}`);
      return r.data;
    }
    async function card(page, label, value, note) {
      const c = page
        .locator('app-overview app-summary-card')
        .filter({ has: page.locator('small', { hasText: new RegExp('^' + label + '$') }) });
      assert.equal(await c.locator('strong').innerText(), String(value));
      if (note) assert.ok((await c.innerText()).includes(note));
    }
    async function loaded(page) {
      await page.waitForFunction(() => {
        const b = Array.from(document.querySelectorAll('app-overview button')).find((x) =>
          x.textContent.includes('Atualizar visão geral'),
        );
        return b && !b.disabled;
      });
    }
    try {
      for (const role of ['A', 'B', 'C', 'student']) {
        const r = await provisioner.auth.admin.createUser({
          email: `dashboard-${role}-${school}@example.test`,
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
      sql(`insert into schools(id,name) values('${school}','Dashboard escola local'),('${otherSchool}','Dashboard outra escola');
      insert into admins(id,school_id,name,email,role,auth_user_id,status) values
      ('${A}',null,'Dashboard A','${users[0].email}','ADMIN_A','${users[0].id}','ACTIVE'),
      ('${B}','${school}','Dashboard B','${users[1].email}','ADMIN_B','${users[1].id}','ACTIVE'),
      ('${C}','${school}','Dashboard C','${users[2].email}','ADMIN_C','${users[2].id}','ACTIVE'),
      ('${otherC}','${otherSchool}','Dashboard C externo','external-${school}@example.test','ADMIN_C',null,'INACTIVE');
      insert into classes(id,school_id,segment,grade,name,points_class_balance) values
      ('${class1}','${school}','Livre','1','Dashboard origem',1234),('${class2}','${school}','Livre','2','Dashboard destino',456),('${foreignClass}','${otherSchool}','Livre','3','Turma externa',789);
      insert into students(id,school_id,class_id,name,registration,status,auth_user_id,points_student_balance) values
      ('${student}','${school}','${class1}','Dashboard aluno','001','ACTIVE','${users[3].id}',2000),('${inactiveStudent}','${school}','${class1}','Dashboard inativo','002','INACTIVE',null,0),('${foreignStudent}','${otherSchool}','${foreignClass}','Aluno externo','001','ACTIVE',null,0);
      insert into machines(id,school_id,name,status) values('${machine}','${school}','Máquina estrutural local','OFFLINE');`);
      await rpc(clients[0], 'update_binbazar_price_cap_v1', { p_max_price: 2000 });
      for (const [id, name, stock] of [
        [product, 'Dashboard produto', 2],
        [zeroProduct, 'Dashboard esgotado', 0],
        [unlimitedProduct, 'Dashboard ilimitado', null],
      ])
        await rpc(clients[1], 'create_admin_binbazar_product_v1', {
          p_reward_id: id,
          p_name: name,
          p_description: null,
          p_category: null,
          p_cost_points: 500,
          p_stock_qty: stock,
          p_is_active: true,
        });
      sql(
        `insert into rewards(id,school_id,name,cost_points,is_active,stock_qty) values('${foreignProduct}','${otherSchool}','Produto externo',500,true,0);`,
      );
      const request = randomUUID();
      await rpc(clients[2], 'create_class_change_request_v1', {
        p_request_id: request,
        p_student_id: student,
        p_destination_class_id: class2,
      });
      const redemption = (
        await rpc(clients[3], 'request_redemption_v1', {
          p_request_id: randomUUID(),
          p_reward_id: product,
        })
      )[0];
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
      const dashboardCalls = [];
      page.on('request', (r) => {
        if (r.url().includes('/rest/v1/'))
          dashboardCalls.push({ path: new URL(r.url()).pathname, body: r.postDataJSON() });
      });
      await page.goto(url);
      async function login(user) {
        await page.getByLabel('E-mail institucional', { exact: true }).fill(user.email);
        await page.getByLabel('Senha', { exact: true }).fill(password);
        await page.getByRole('button', { name: 'Acessar o Admin', exact: true }).click();
        await page.locator('app-overview').waitFor();
        await loaded(page);
      }
      async function logout() {
        await page.getByRole('button', { name: 'Sair', exact: true }).click();
        await page.getByLabel('Senha', { exact: true }).waitFor();
      }
      await login(users[0]);
      const schools = await rpc(clients[0], 'get_admin_schools_v1'),
        admins = await rpc(clients[0], 'get_managed_admins_v1');
      await card(page, 'Escolas cadastradas', schools.length);
      await card(
        page,
        'Alunos cadastrados',
        schools.reduce((n, s) => n + Number(s.student_count), 0),
      );
      await card(
        page,
        'Máquinas cadastradas',
        schools.reduce((n, s) => n + Number(s.machine_count), 0),
      );
      await card(
        page,
        'Administradores',
        admins.length,
        `${admins.filter((a) => a.status === 'ACTIVE').length} ACTIVE · ${admins.filter((a) => a.status === 'INACTIVE').length} INACTIVE`,
      );
      await card(page, 'Sem vínculo de acesso', admins.filter((a) => !a.access_linked).length);
      await card(page, 'Teto do BinBazar', '2.000');
      await logout();
      await login(users[1]);
      await card(page, 'Alunos ACTIVE', '1', '1 INACTIVE');
      await card(page, 'Turmas disponíveis', '2');
      await card(page, 'Administradores C', '1', '1 ACTIVE');
      await card(page, 'Trocas PENDING', '1');
      await card(page, 'Resgates PENDING', '1');
      await card(page, 'Produtos ativos', '3', '1 ativos sem estoque');
      const overview = page.locator('app-overview');
      assert.equal(await overview.getByText('Dashboard esgotado', { exact: true }).count(), 1);
      assert.equal(await overview.getByText('1234 XP', { exact: true }).count(), 1);
      for (const name of [
        'Aluno externo',
        'Produto externo',
        'Dashboard C externo',
        'Máquina estrutural local',
      ])
        assert.equal(await overview.getByText(name, { exact: true }).count(), 0);
      await rpc(clients[1], 'approve_class_change_request_v1', { p_request_id: request });
      await rpc(clients[1], 'deliver_admin_redemption_v1', {
        p_redemption_id: redemption.redemption_id,
      });
      await page.getByRole('button', { name: 'Atualizar visão geral' }).click();
      await loaded(page);
      await card(page, 'Trocas PENDING', '0');
      await card(page, 'Resgates PENDING', '0');
      assert.equal(sql(`select class_id from students where id='${student}'`), class2);
      await logout();
      await login(users[2]);
      await card(page, 'Minhas solicitações PENDING', '0');
      await card(page, 'Resgates PENDING', '0');
      await card(page, 'Produtos ativos', '3');
      await card(page, 'Alunos ACTIVE', '1');
      assert.equal(
        await page.getByRole('button', { name: 'Administradores', exact: true }).count(),
        0,
      );
      const own = randomUUID();
      await rpc(clients[2], 'create_class_change_request_v1', {
        p_request_id: own,
        p_student_id: student,
        p_destination_class_id: class1,
      });
      await page.getByRole('button', { name: 'Atualizar visão geral' }).click();
      await loaded(page);
      await card(page, 'Minhas solicitações PENDING', '1');
      await page.reload();
      await loaded(page);
      await card(page, 'Minhas solicitações PENDING', '1');
      await card(page, 'Teto do BinBazar', '2.000');
      assert.ok(dashboardCalls.every((c) => c.path.startsWith('/rest/v1/rpc/get_')));
      dashboardCalls.forEach((c) => assert.deepEqual(c.body, {}));
      assert.ok(!(await overview.innerText()).includes('Totem'));
      await page.close();
    } finally {
      await browser?.close();
      const g = JSON.parse(original);
      sql(
        `delete from admin_structure_creation_receipts where created_by_admin_id in ('${A}','${B}','${C}');delete from audit_logs where school_id in ('${school}','${otherSchool}') or actor_id='${A}';delete from class_change_requests where school_id in ('${school}','${otherSchool}');delete from redemptions where school_id in ('${school}','${otherSchool}');delete from rewards where school_id in ('${school}','${otherSchool}');delete from students where school_id in ('${school}','${otherSchool}');delete from classes where school_id in ('${school}','${otherSchool}');delete from machines where school_id='${school}';delete from admins where id in ('${A}','${B}','${C}','${otherC}');delete from schools where id in ('${school}','${otherSchool}');update global_economic_settings set binbazar_max_price=${g.binbazar_max_price ?? 'NULL'},created_at='${g.created_at}',updated_at='${g.updated_at}';`,
      );
      for (const client of clients) await client.auth.signOut();
      for (const user of users)
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
