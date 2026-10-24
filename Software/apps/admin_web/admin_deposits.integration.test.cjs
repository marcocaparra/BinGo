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
  'local real Auth/RPC/Angular deposits: A global, B/C scoped and snapshots preserved',
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
    for (const value of [config.API_URL, url])
      assert.ok(['127.0.0.1', 'localhost'].includes(new URL(value).hostname));
    const opts = { auth: { persistSession: false, autoRefreshToken: false } };
    const provisioner = createClient(config.API_URL, config.SERVICE_ROLE_KEY, opts);
    const schools = [randomUUID(), randomUUID()];
    const classes = [randomUUID(), randomUUID()];
    const machines = [randomUUID(), randomUUID()];
    const students = [randomUUID(), randomUUID()];
    const deposits = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
    const events = deposits.map(() => randomUUID());
    const users = [];
    const clients = [];
    const admins = [];
    const password = randomBytes(24).toString('base64url');
    let browser;
    try {
      sql(`
        insert into schools(id,name) values ('${schools[0]}','Descartes local Norte'),('${schools[1]}','Descartes local Sul');
        insert into classes(id,school_id,segment,grade,name) values
          ('${classes[0]}','${schools[0]}','FUNDAMENTAL_II','9','9A local'),
          ('${classes[1]}','${schools[1]}','FUNDAMENTAL_II','8','8B local');
        insert into machines(id,school_id,name,status) values
          ('${machines[0]}','${schools[0]}','Totem descarte Norte','ONLINE'),
          ('${machines[1]}','${schools[1]}','Totem descarte Sul','ONLINE');
        insert into students(id,school_id,class_id,name,status) values
          ('${students[0]}','${schools[0]}','${classes[0]}','Aluno descarte Norte','ACTIVE'),
          ('${students[1]}','${schools[1]}','${classes[1]}','Aluno descarte Sul','ACTIVE');
        insert into deposits(id,event_id,school_id,machine_id,class_id,student_id,is_valid,detected_type,points_awarded_student,points_awarded_class,waste_category_id,category_source,bonus_rate_applied,bonus_bincoins_awarded,created_at) values
          ('${deposits[0]}','${events[0]}','${schools[0]}','${machines[0]}','${classes[0]}','${students[0]}',true,'BATTERY',1600,1900,(select id from waste_categories where code='BATTERY'),'AI_CONFIRMED',1,800,'2026-10-01T12:00:00Z'),
          ('${deposits[1]}','${events[1]}','${schools[0]}','${machines[0]}','${classes[0]}',null,true,null,0,1900,(select id from waste_categories where code='UNKNOWN'),'UNIDENTIFIED',0,0,'2026-10-01T11:00:00Z'),
          ('${deposits[2]}','${events[2]}','${schools[0]}','${machines[0]}','${classes[0]}',null,false,null,0,0,null,null,0,0,'2026-10-01T10:00:00Z'),
          ('${deposits[3]}','${events[3]}','${schools[1]}','${machines[1]}','${classes[1]}','${students[1]}',true,'CABLE_WIRE',900,1900,(select id from waste_categories where code='CABLE_WIRE'),'USER_CORRECTED',0.125,100,'2026-10-01T13:00:00Z');
      `);
      for (const [i, role] of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C', 'INACTIVE', 'UNLINKED'].entries()) {
        const created = await provisioner.auth.admin.createUser({
          email: `deposits-${i}-${schools[0]}@example.test`,
          password,
          email_confirm: true,
        });
        assert.equal(created.error, null);
        users.push(created.data.user);
        if (role !== 'UNLINKED') {
          const id = randomUUID();
          admins.push(id);
          sql(`insert into admins(id,name,email,role,school_id,status,auth_user_id) values
            ('${id}','Dep admin ${i}','${created.data.user.email}','${role === 'INACTIVE' ? 'ADMIN_C' : role}',${role === 'ADMIN_A' ? 'null' : `'${schools[0]}'`},'${role === 'INACTIVE' ? 'INACTIVE' : 'ACTIVE'}','${created.data.user.id}');`);
        }
        const client = createClient(config.API_URL, config.ANON_KEY, opts);
        assert.equal(
          (await client.auth.signInWithPassword({ email: created.data.user.email, password }))
            .error,
          null,
        );
        clients.push(client);
        const result = await client.rpc('get_admin_deposits_v1');
        if (i >= 3) {
          assert.equal(result.error.code, '42501');
          continue;
        }
        assert.equal(result.error, null);
        assert.ok(result.data.some((row) => row.deposit_id === deposits[0]));
        if (i === 0) assert.ok(result.data.some((row) => row.deposit_id === deposits[3]));
        else assert.ok(result.data.every((row) => row.school_id === schools[0]));
        const identified = result.data.find((row) => row.deposit_id === deposits[0]);
        assert.deepEqual(
          [
            identified.student_name,
            identified.bonus_bincoins_awarded,
            identified.points_awarded_student,
            identified.points_awarded_class,
          ],
          ['Aluno descarte Norte', 800, 1600, 1900],
        );
        assert.equal(result.data.find((row) => row.deposit_id === deposits[1]).student_name, null);
      }
      assert.ok((await provisioner.rpc('get_admin_deposits_v1')).error);

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
        await page.getByRole('button', { name: 'Descartes', exact: true }).click();
        await page.getByText('Aluno descarte Norte', { exact: true }).waitFor();
        assert.equal(
          await page.getByText('Aluno descarte Sul', { exact: true }).count(),
          i === 0 ? 1 : 0,
        );
        await page.getByText('Sem identificação', { exact: true }).first().waitFor();
        await page.getByRole('button', { name: 'Atualizar descartes', exact: true }).click();
        await page.getByText('Aluno descarte Norte', { exact: true }).waitFor();
        await page.getByRole('button', { name: 'Sair', exact: true }).click();
        await page.getByRole('button', { name: 'Acessar o Admin', exact: true }).waitFor();
      }
    } finally {
      await browser?.close();
      sql(`
        delete from deposits where id in ('${deposits.join("','")}');
        delete from students where id in ('${students.join("','")}');
        delete from machines where id in ('${machines.join("','")}');
        delete from classes where id in ('${classes.join("','")}');
        delete from admins where id in ('${admins.join("','")}');
        delete from schools where id in ('${schools.join("','")}');
      `);
      for (const client of clients) await client.auth.signOut();
      for (const user of users)
        assert.equal((await provisioner.auth.admin.deleteUser(user.id)).error, null);
    }
  },
);
