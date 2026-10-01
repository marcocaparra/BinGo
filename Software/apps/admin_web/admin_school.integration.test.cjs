const { test } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { randomUUID, randomBytes } = require('node:crypto');
const { createClient } = require('@supabase/supabase-js');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
function sql(command) {
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
    { input: command, encoding: 'utf8', windowsHide: true },
  ).trim();
}
test(
  'real local B/C Auth → context → school RPC → Angular CRUD, isolation and transactional audit',
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
      assert.ok(
        ['localhost', '127.0.0.1'].includes(new URL(url).hostname),
        'Somente loopback local',
      );
    const options = {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    };
    // Provisionamento efemero da fixture somente neste processo local; browser recebe apenas anon.
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options);
    const users = [];
    const [
      school,
      otherSchool,
      originalClass,
      destinationClass,
      otherClass,
      otherStudent,
      adminB,
      adminC,
    ] = Array.from({ length: 8 }, () => randomUUID());
    const password = randomBytes(24).toString('base64url');
    let browser;
    try {
      for (const role of ['B', 'C']) {
        const created = await provisioner.auth.admin.createUser({
          email: `school-${role}-${school}@example.test`,
          password,
          email_confirm: true,
        });
        assert.equal(created.error, null);
        users.push(created.data.user);
      }
      sql(`insert into public.schools(id,name) values('${school}','School smoke'),('${otherSchool}','External smoke');
      insert into public.classes(id,school_id,segment,grade,name,points_class_balance) values
      ('${originalClass}','${school}','Livre','1','Original smoke',1900),('${destinationClass}','${school}','Livre','2','Destino smoke',2300),('${otherClass}','${otherSchool}','Livre','3','External smoke',500);
      insert into public.students(id,school_id,class_id,name) values('${otherStudent}','${otherSchool}','${otherClass}','External student');
      insert into public.admins(id,school_id,name,email,role,auth_user_id) values
      ('${adminB}','${school}','B local','${users[0].email}','ADMIN_B','${users[0].id}'),('${adminC}','${school}','C local','${users[1].email}','ADMIN_C','${users[1].id}');`);
      const clientB = createClient(config.API_URL, config.ANON_KEY, options);
      assert.equal(
        (await clientB.auth.signInWithPassword({ email: users[0].email, password })).error,
        null,
      );
      assert.equal((await clientB.rpc('get_my_admin_context_v1')).data[0].school_id, school);
      assert.deepEqual((await clientB.rpc('get_admin_students_v1')).data, []);
      assert.equal((await clientB.rpc('get_admin_classes_v1')).data.length, 2);
      assert.ok(
        (
          await clientB.rpc('create_admin_student_v1', {
            p_name: 'Forged',
            p_email: null,
            p_registration: '1',
            p_class_id: originalClass,
            p_school_id: otherSchool,
          })
        ).error,
      );
      assert.equal(
        (
          await clientB.rpc('create_admin_student_v1', {
            p_name: 'External',
            p_email: null,
            p_registration: '1',
            p_class_id: otherClass,
          })
        ).error.code,
        '42501',
      );
      assert.equal(
        (
          await clientB
            .from('students')
            .insert({ school_id: school, class_id: originalClass, name: 'Direct' })
        ).error.code,
        '42501',
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
      async function login(user) {
        await page.getByLabel('E-mail institucional', { exact: true }).fill(user.email);
        await page.getByLabel('Senha', { exact: true }).fill(password);
        await page.getByRole('button', { name: 'Acessar o Admin' }).click();
        await page.getByRole('button', { name: 'Alunos', exact: true }).click();
      }
      await page.goto(browserUrl);
      await login(users[0]);
      await page.getByRole('heading', { name: 'Nenhum aluno cadastrado' }).waitFor();
      await page.getByRole('button', { name: 'Cadastrar aluno' }).click();
      let dialog = page.getByRole('dialog');
      await dialog.getByLabel('Nome completo').fill('Aluno smoke local');
      await dialog.getByLabel('E-mail institucional').fill('student@school.example.test');
      await dialog.getByLabel('RA ou matrícula').fill('0000123');
      await dialog.getByLabel('Turma', { exact: true }).selectOption(originalClass);
      await dialog.getByRole('button', { name: 'Cadastrar aluno' }).click();
      await page.getByText('Aluno smoke local', { exact: true }).waitFor();
      const student = (await clientB.rpc('get_admin_students_v1')).data[0];
      assert.equal(student.registration, '0000123');
      assert.equal(student.points_student_balance, 0);
      const technicalAuth = randomUUID();
      sql(
        `update public.students set points_student_balance=800,pin_hash='local-test-protected',auth_user_id='${technicalAuth}',is_activated=true where id='${student.student_id}';`,
      );
      await page.reload();
      await page.getByRole('button', { name: 'Alunos', exact: true }).click();
      await page.getByRole('button', { name: 'Editar', exact: true }).click();
      dialog = page.getByRole('dialog');
      await dialog.getByLabel('Nome completo').fill('Aluno editado local');
      await dialog.getByLabel('E-mail institucional').fill('edited@school.example.test');
      await dialog.getByLabel('RA ou matrícula').fill('0000456');
      await dialog.getByLabel('Turma', { exact: true }).selectOption(destinationClass);
      await dialog.getByLabel('Estado').selectOption('INACTIVE');
      await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Aluno editado local', { exact: true }).waitFor();
      await page.getByText('Inativo', { exact: true }).waitFor();
      assert.equal(
        sql(
          `select points_student_balance||'|'||pin_hash||'|'||auth_user_id||'|'||is_activated from public.students where id='${student.student_id}';`,
        ),
        `800|local-test-protected|${technicalAuth}|true`,
      );
      await page.getByRole('button', { name: 'Turmas', exact: true }).click();
      await page.getByRole('button', { name: 'Criar turma' }).click();
      dialog = page.getByRole('dialog');
      await dialog.getByLabel('Nome da turma').fill('Criada local');
      await dialog.getByLabel('Segmento').fill('Segmento local');
      await dialog.getByLabel('Série/grade').fill('Etapa local');
      await dialog.getByRole('button', { name: 'Criar turma' }).click();
      await page.getByText('Criada local', { exact: true }).waitFor();
      await page
        .locator('app-entity-row')
        .filter({ hasText: 'Criada local' })
        .getByRole('button', { name: 'Editar' })
        .click();
      dialog = page.getByRole('dialog');
      await dialog.getByLabel('Nome da turma').fill('Editada local');
      await dialog.getByLabel('Segmento').fill('Outro segmento');
      await dialog.getByLabel('Série/grade').fill('Outra etapa');
      await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
      await page.getByText('Editada local', { exact: true }).waitFor();
      assert.equal(
        sql(
          `select points_class_balance from public.classes where school_id='${school}' and name='Editada local';`,
        ),
        '0',
      );
      assert.equal(sql(`select count(*) from public.audit_logs where actor_id='${adminB}';`), '4');
      const audit = JSON.parse(
        sql(
          `select metadata from public.audit_logs where actor_id='${adminB}' and action='ADMIN_STUDENT_UPDATED_V1';`,
        ),
      );
      assert.equal(audit.old.class_id, originalClass);
      assert.equal(audit.new.class_id, destinationClass);
      assert.equal(audit.old.status, 'ACTIVE');
      assert.equal(audit.new.status, 'INACTIVE');
      await page.getByRole('button', { name: 'Sair', exact: true }).click();
      await login(users[1]);
      await page.getByText('Aluno editado local', { exact: true }).waitFor();
      assert.equal(await page.getByRole('button', { name: 'Editar', exact: true }).count(), 0);
      assert.equal(await page.getByRole('button', { name: 'Cadastrar aluno' }).count(), 0);
      await page.getByRole('button', { name: 'Consultar', exact: true }).click();
      await page
        .getByRole('dialog')
        .getByText(/800 BinCoins · 2300 XP/)
        .waitFor();
      const clientC = createClient(config.API_URL, config.ANON_KEY, options);
      assert.equal(
        (await clientC.auth.signInWithPassword({ email: users[1].email, password })).error,
        null,
      );
      assert.equal((await clientC.rpc('get_admin_students_v1')).data.length, 1);
      for (const [rpc, args] of [
        [
          'create_admin_student_v1',
          { p_name: 'Forbidden', p_email: null, p_registration: '2', p_class_id: originalClass },
        ],
        [
          'update_admin_student_v1',
          {
            p_student_id: student.student_id,
            p_name: 'Forbidden',
            p_email: null,
            p_registration: '2',
            p_class_id: originalClass,
            p_status: 'ACTIVE',
          },
        ],
        ['create_admin_class_v1', { p_segment: 's', p_grade: 'g', p_name: 'Forbidden' }],
        [
          'update_admin_class_v1',
          { p_class_id: originalClass, p_segment: 's', p_grade: 'g', p_name: 'Forbidden' },
        ],
      ])
        assert.equal((await clientC.rpc(rpc, args)).error.code, '42501', rpc);
      assert.equal(
        (
          await clientB.rpc('update_admin_student_v1', {
            p_student_id: otherStudent,
            p_name: 'Forged',
            p_email: null,
            p_registration: '2',
            p_class_id: originalClass,
            p_status: 'ACTIVE',
          })
        ).error.code,
        '42501',
      );
      sql(`update public.admins set status='INACTIVE' where id='${adminB}';`);
      assert.equal(
        (await clientB.rpc('get_admin_students_v1')).error.code,
        '42501',
        'ACTIVE revalidado a cada RPC',
      );
      assert.equal(sql(`select count(*) from public.audit_logs where actor_id='${adminC}';`), '0');
      await clientB.auth.signOut({ scope: 'local' });
      await clientC.auth.signOut({ scope: 'local' });
    } finally {
      await browser?.close();
      sql(`delete from public.audit_logs where school_id in ('${school}','${otherSchool}');
      delete from public.students where school_id in ('${school}','${otherSchool}');
      delete from public.classes where school_id in ('${school}','${otherSchool}');
      delete from public.admins where id in ('${adminB}','${adminC}');
      delete from public.schools where id in ('${school}','${otherSchool}');`);
      for (const user of users.reverse())
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
