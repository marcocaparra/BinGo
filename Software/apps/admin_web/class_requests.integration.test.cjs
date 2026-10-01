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
  'local Auth: C creates → B approves → C sees APPROVED; stale and canceled cannot approve',
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
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options);
    const [school, student, machine, event, adminB, adminC] = Array.from({ length: 6 }, () =>
      randomUUID(),
    );
    const classrooms = Array.from({ length: 3 }, () => randomUUID());
    const password = randomBytes(24).toString('base64url');
    const users = [];
    let browser;
    try {
      for (const role of ['B', 'C']) {
        const result = await provisioner.auth.admin.createUser({
          email: `requests-${role}-${school}@example.test`,
          password,
          email_confirm: true,
        });
        assert.equal(result.error, null);
        users.push(result.data.user);
      }
      sql(`insert into public.schools(id,name) values('${school}','Class change smoke');
      insert into public.classes(id,school_id,segment,grade,name,points_class_balance) values
      ('${classrooms[0]}','${school}','Livre','1','Classe A local',1900),('${classrooms[1]}','${school}','Livre','2','Classe B local',2000),('${classrooms[2]}','${school}','Livre','3','Classe C local',3000);
      insert into public.students(id,school_id,class_id,name,registration,points_student_balance,pin_hash,is_activated) values('${student}','${school}','${classrooms[0]}','Aluno troca local','001',800,'local-protected',true);
      insert into public.admins(id,school_id,name,email,role,auth_user_id) values
      ('${adminB}','${school}','B troca local','${users[0].email}','ADMIN_B','${users[0].id}'),('${adminC}','${school}','C troca local','${users[1].email}','ADMIN_C','${users[1].id}');
      insert into public.machines(id,school_id,name,status) values('${machine}','${school}','Historica','ONLINE');
      insert into public.deposits(event_id,school_id,machine_id,class_id,student_id,is_valid,waste_category_id,category_source,points_awarded_student,points_awarded_class)
      values('${event}','${school}','${machine}','${classrooms[0]}','${student}',true,(select id from public.waste_categories where code='PERIPHERAL'),'AI_CONFIRMED',800,1900);`);
      const historical = sql(
        `select row_to_json(d) from public.deposits d where event_id='${event}';`,
      );
      const originalStudent = JSON.parse(
        sql(`select row_to_json(s) from public.students s where id='${student}';`),
      );
      const b = createClient(config.API_URL, config.ANON_KEY, options),
        c = createClient(config.API_URL, config.ANON_KEY, options);
      for (const [client, user] of [
        [b, users[0]],
        [c, users[1]],
      ]) {
        assert.equal(
          (await client.auth.signInWithPassword({ email: user.email, password })).error,
          null,
        );
        assert.equal((await client.rpc('get_my_admin_context_v1')).data[0].school_id, school);
      }
      browser = await chromium.launch({
        headless: true,
        executablePath:
          process.env.BINGO_BROWSER_PATH ||
          'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
      });
      const pageB = await browser.newPage(),
        pageC = await browser.newPage();
      for (const [page, user] of [
        [pageB, users[0]],
        [pageC, users[1]],
      ]) {
        await page.route('**/supabase-config.json', (route) =>
          route.fulfill({
            json: { SUPABASE_URL: config.API_URL, SUPABASE_PUBLISHABLE_KEY: config.ANON_KEY },
          }),
        );
        await page.goto(browserUrl);
        await page.getByLabel('E-mail institucional', { exact: true }).fill(user.email);
        await page.getByLabel('Senha', { exact: true }).fill(password);
        await page.getByRole('button', { name: 'Acessar o Admin' }).click();
        await page.getByRole('button', { name: 'Sair', exact: true }).waitFor();
      }
      async function refreshC() {
        await pageC.reload();
        await pageC.getByRole('button', { name: 'Solicitações', exact: true }).click();
      }
      async function createFromC(destination) {
        await refreshC();
        await pageC.getByRole('button', { name: 'Solicitar troca de turma' }).click();
        const dialog = pageC.getByRole('dialog');
        await dialog.getByLabel('Aluno', { exact: true }).selectOption(student);
        await dialog.getByLabel('Nova turma').selectOption(destination);
        await dialog.getByRole('button', { name: 'Enviar solicitação' }).click();
        await pageC.getByText('Solicitação enviada.', { exact: true }).waitFor();
        const rows = await c.rpc('get_class_change_requests_v1');
        assert.equal(rows.error, null);
        return rows.data.find((r) => r.status === 'PENDING');
      }
      // C cria -> B aprova -> C acompanha o terminal; replays nao duplicam logs.
      const first = await createFromC(classrooms[1]);
      assert.equal(first.source_class_id, classrooms[0]);
      assert.equal(
        sql(`select class_id from public.students where id='${student}';`),
        classrooms[0],
      );
      await pageB.getByRole('button', { name: /Pendências/ }).click();
      await pageB.getByRole('button', { name: 'Analisar' }).click();
      await pageB.getByRole('dialog').getByRole('button', { name: 'Aprovar troca' }).click();
      await pageB.getByText('Aprovada', { exact: true }).waitFor();
      assert.equal(
        sql(`select class_id from public.students where id='${student}';`),
        classrooms[1],
      );
      await refreshC();
      await pageC.getByText('Aprovada', { exact: true }).waitFor();
      assert.equal(
        (await b.rpc('approve_class_change_request_v1', { p_request_id: first.request_id })).error,
        null,
      );
      assert.equal(
        (
          await c.rpc('create_class_change_request_v1', {
            p_request_id: first.request_id,
            p_student_id: student,
            p_destination_class_id: classrooms[1],
          })
        ).error,
        null,
      );
      assert.equal(
        sql(
          `select count(*) from public.audit_logs where metadata->>'request_id'='${first.request_id}';`,
        ),
        '2',
      );
      const afterApprove = JSON.parse(
        sql(`select row_to_json(s) from public.students s where id='${student}';`),
      );
      delete originalStudent.class_id;
      delete afterApprove.class_id;
      assert.deepEqual(afterApprove, originalStudent);
      // Volta a A por operacao B autorizada para preparar o cenario A->B antigo.
      const direct = async (classroom) => {
        const result = await b.rpc('update_admin_student_v1', {
          p_student_id: student,
          p_name: 'Aluno troca local',
          p_email: null,
          p_registration: '001',
          p_class_id: classroom,
          p_status: 'ACTIVE',
        });
        assert.equal(result.error, null);
      };
      await direct(classrooms[0]);
      const stale = await createFromC(classrooms[1]);
      await direct(classrooms[2]);
      const oldApprove = await b.rpc('approve_class_change_request_v1', {
        p_request_id: stale.request_id,
      });
      assert.equal(oldApprove.error.message, 'CLASS_CHANGE_REQUEST_STALE');
      assert.equal(
        sql(`select class_id from public.students where id='${student}';`),
        classrooms[2],
      );
      assert.equal(
        (await c.rpc('get_class_change_requests_v1')).data.find(
          (r) => r.request_id === stale.request_id,
        ).is_stale,
        true,
      );
      await pageB.reload();
      await pageB.getByRole('button', { name: /Pendências/ }).click();
      await pageB.getByRole('button', { name: 'Analisar' }).click();
      assert.equal(
        await pageB.getByRole('dialog').getByRole('button', { name: 'Aprovar troca' }).isEnabled(),
        false,
      );
      await pageB.getByRole('dialog').getByRole('button', { name: 'Rejeitar' }).click();
      await pageB.getByText('Rejeitada', { exact: true }).waitFor();
      assert.equal(
        (await b.rpc('reject_class_change_request_v1', { p_request_id: stale.request_id })).error,
        null,
      );
      assert.equal(
        sql(
          `select count(*) from public.audit_logs where metadata->>'request_id'='${stale.request_id}';`,
        ),
        '2',
      );
      // C cria -> C cancela -> B nao consegue aprovar; historico continua visivel.
      const canceled = await createFromC(classrooms[1]);
      await pageC
        .locator('app-class-requests app-entity-row')
        .filter({ hasText: 'Pendente' })
        .getByRole('button', { name: 'Cancelar' })
        .click();
      await pageC
        .getByRole('dialog')
        .getByRole('button', { name: 'Confirmar cancelamento' })
        .click();
      await pageC.getByText('Cancelada', { exact: true }).waitFor();
      assert.equal(
        (await b.rpc('approve_class_change_request_v1', { p_request_id: canceled.request_id }))
          .error.message,
        'CLASS_CHANGE_DECISION_CONFLICT',
      );
      assert.equal(
        (await c.rpc('cancel_class_change_request_v1', { p_request_id: canceled.request_id }))
          .error,
        null,
      );
      assert.equal(
        sql(`select class_id from public.students where id='${student}';`),
        classrooms[2],
      );
      assert.equal(
        sql(
          `select count(*) from public.audit_logs where metadata->>'request_id'='${canceled.request_id}';`,
        ),
        '2',
      );
      assert.equal(
        sql(`select row_to_json(d) from public.deposits d where event_id='${event}';`),
        historical,
      );
      assert.equal((await b.from('class_change_requests').select('*')).error.code, '42501');
      assert.equal((await c.rpc('get_class_change_requests_v1')).data.length, 3);
      await b.auth.signOut({ scope: 'local' });
      await c.auth.signOut({ scope: 'local' });
    } finally {
      await browser?.close();
      for (const table of [
        'class_change_requests',
        'audit_logs',
        'deposits',
        'machines',
        'students',
        'classes',
        'admins',
        'schools',
      ])
        sql(
          `delete from public.${table} where ${table === 'schools' ? 'id' : 'school_id'}='${school}';`,
        );
      for (const user of users.reverse())
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
