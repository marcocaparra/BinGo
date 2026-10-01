const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { installSupabaseFixture, submitLogin } = require('./test/supabase-fixture.cjs');
const url = process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/';
let browser;
before(async () => {
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.BINGO_BROWSER_PATH ||
      'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  });
});
after(async () => {
  await browser?.close();
});
async function open(options = {}, view = 'Alunos') {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, { role: 'ADMIN_B', ...options });
  await page.goto(url);
  await submitLogin(page);
  await page.getByRole('button', { name: view, exact: true }).click();
  return { page, fixture };
}
test('B reads RPC students, balances and class XP without demo data or scenario selector', async () => {
  const { page, fixture } = await open();
  try {
    await page.getByText('Aluno RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
    assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
    assert.equal(await page.getByText('800', { exact: true }).count(), 1);
    assert.equal(await page.getByText('1900', { exact: true }).count(), 1);
    assert.equal(await page.getByText('Ana Clara M.', { exact: true }).count(), 0);
    assert.ok(fixture.calls.some((c) => c.path.endsWith('get_admin_students_v1')));
  } finally {
    await page.close();
  }
});
test('C consults only, including historical null RA/email, with no write buttons or classes view', async () => {
  const { page } = await open({
    role: 'ADMIN_C',
    students: [
      {
        student_id: 'student-null',
        name: 'Historico',
        registration: null,
        email: null,
        class_id: '20000000-0000-4000-8000-000000000001',
        status: 'INACTIVE',
        points_student_balance: 42,
      },
    ],
  });
  try {
    await page.getByRole('button', { name: 'Consultar', exact: true }).click();
    const dialog = page.getByRole('dialog');
    assert.equal(await dialog.getByLabel('Nome completo').getAttribute('readonly'), '');
    assert.equal(await dialog.getByLabel('RA ou matrícula').inputValue(), '');
    await dialog.getByText(/42 BinCoins · 1900 XP/).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Cadastrar aluno' }).count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Editar', exact: true }).count(), 0);
    assert.equal(await page.getByRole('button', { name: 'Turmas', exact: true }).count(), 0);
    assert.equal(await dialog.getByRole('button', { name: 'Salvar alterações' }).count(), 0);
  } finally {
    await page.close();
  }
});
test('loading, empty and error are real states; retry never falls back to mocks', async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  const { page, fixture } = await open({ schoolWait: gate });
  try {
    await page.getByRole('heading', { name: 'Carregando alunos…' }).waitFor();
    release();
    await page.getByText('Aluno RPC', { exact: true }).waitFor();
    fixture.schoolError = true;
    await page.getByRole('button', { name: 'Turmas', exact: true }).click();
    await page.getByRole('heading', { name: 'Não foi possível carregar turmas' }).waitFor();
    assert.equal(await page.getByText('9º A', { exact: true }).count(), 0);
    fixture.schoolError = false;
    fixture.students = [];
    fixture.classes = [];
    await page.getByRole('button', { name: 'Tentar novamente' }).click();
    await page.getByRole('heading', { name: 'Nenhuma turma cadastrada' }).waitFor();
    await page.getByRole('button', { name: 'Alunos', exact: true }).click();
    await page.getByRole('heading', { name: 'Nenhum aluno cadastrado' }).waitFor();
    fixture.schoolError = true;
    await page.getByRole('button', { name: 'Turmas', exact: true }).click();
    await page.getByRole('button', { name: 'Alunos', exact: true }).click();
    await page.getByRole('heading', { name: 'Não foi possível carregar alunos' }).waitFor();
    assert.equal(await page.locator('tbody tr').count(), 0);
    assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
  } finally {
    release();
    await page.close();
  }
});
test('B creates and edits a student by IDs, preserving leading zero RA, balance and class scope', async () => {
  const { page, fixture } = await open();
  try {
    await page.getByRole('button', { name: 'Cadastrar aluno' }).click();
    let dialog = page.getByRole('dialog');
    await dialog.getByLabel('Nome completo').fill('Novo RPC');
    await dialog.getByLabel('E-mail institucional').fill('novo@example.test');
    await dialog.getByLabel('RA ou matrícula').fill('000009');
    await dialog.getByLabel('Turma', { exact: true }).selectOption(fixture.classes[0].class_id);
    await dialog.getByRole('button', { name: 'Cadastrar aluno' }).click();
    await page.getByText('Novo RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('Novo RPC', { exact: true }).count(), 1);
    let row = page.getByRole('row').filter({ hasText: 'Novo RPC' });
    await row.getByRole('button', { name: 'Editar' }).click();
    dialog = page.getByRole('dialog');
    assert.equal(await dialog.getByLabel('RA ou matrícula').inputValue(), '000009');
    assert.equal(
      await dialog.locator('[name="balance"],[name="pin_hash"],[name="auth_user_id"]').count(),
      0,
    );
    await dialog.getByLabel('Nome completo').fill('Editado RPC');
    await dialog.getByLabel('E-mail institucional').fill('');
    await dialog.getByLabel('RA ou matrícula').fill('000010');
    await dialog.getByLabel('Turma', { exact: true }).selectOption(fixture.classes[1].class_id);
    await dialog.getByLabel('Estado').selectOption('INACTIVE');
    await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
    await page.getByText('Editado RPC', { exact: true }).waitFor();
    row = page.getByRole('row').filter({ hasText: 'Editado RPC' });
    await row.getByText('Inativo', { exact: true }).waitFor();
    await row.getByText('Turma destino RPC', { exact: true }).waitFor();
    const update = fixture.calls.find((c) => c.path.endsWith('update_admin_student_v1'));
    assert.equal(
      update.body.p_student_id,
      fixture.students.find((s) => s.name === 'Editado RPC').student_id,
    );
    assert.equal(update.body.p_email, null);
    assert.equal(update.body.p_registration, '000010');
    assert.equal(update.body.p_status, 'INACTIVE');
    assert.ok(fixture.calls.filter((c) => c.path.endsWith('get_admin_students_v1')).length >= 3);
  } finally {
    await page.close();
  }
});
test('duplicate RA keeps dialog and server snapshot; network mutation error permits retry', async () => {
  const { page, fixture } = await open();
  try {
    await page.getByRole('button', { name: 'Cadastrar aluno' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Nome completo').fill('Duplicado');
    await dialog.getByLabel('RA ou matrícula').fill('0001');
    await dialog.getByLabel('Turma', { exact: true }).selectOption(fixture.classes[0].class_id);
    await dialog.getByRole('button', { name: 'Cadastrar aluno' }).click();
    await dialog
      .getByRole('alert')
      .getByText(/matrícula já está em uso/)
      .waitFor();
    assert.equal(fixture.students.length, 1);
    fixture.schoolError = true;
    await dialog.getByLabel('RA ou matrícula').fill('0002');
    await dialog.getByRole('button', { name: 'Cadastrar aluno' }).click();
    await dialog
      .getByRole('alert')
      .getByText(/Não foi possível salvar/)
      .waitFor();
    fixture.schoolError = false;
    await dialog.getByRole('button', { name: 'Cadastrar aluno' }).click();
    await page.getByText('Duplicado', { exact: true }).waitFor();
  } finally {
    await page.close();
  }
});
test('B creates and edits textual classes without invented status or participation', async () => {
  const { page, fixture } = await open({}, 'Turmas');
  try {
    await page.getByText('Turma RPC', { exact: true }).waitFor();
    assert.equal(await page.locator('app-classes .tag').count(), 0);
    assert.equal(
      await page
        .locator('app-classes')
        .getByText(/%|participação|Ativa|Inativa/)
        .count(),
      0,
    );
    await page.getByRole('button', { name: 'Criar turma' }).click();
    let dialog = page.getByRole('dialog');
    assert.equal(await dialog.getByLabel('Estado').count(), 0);
    await dialog.getByLabel('Nome da turma').fill('Nova RPC');
    await dialog.getByLabel('Segmento').fill('Segmento textual');
    await dialog.getByLabel('Série/grade').fill('Etapa livre');
    await dialog.getByRole('button', { name: 'Criar turma' }).click();
    await page.getByText('Nova RPC', { exact: true }).waitFor();
    await page
      .locator('app-entity-row')
      .filter({ hasText: 'Nova RPC' })
      .getByRole('button', { name: 'Editar' })
      .click();
    dialog = page.getByRole('dialog');
    await dialog.getByLabel('Nome da turma').fill('Nova editada RPC');
    await dialog.getByLabel('Segmento').fill('Outro segmento');
    await dialog.getByLabel('Série/grade').fill('Outra etapa');
    await dialog.getByRole('button', { name: 'Salvar alterações' }).click();
    await page.getByText('Nova editada RPC', { exact: true }).waitFor();
    assert.equal(
      fixture.calls.find((c) => c.path.endsWith('update_admin_class_v1')).body.p_class_id,
      fixture.classes.find((c) => c.name === 'Nova editada RPC').class_id,
    );
    await page.getByRole('button', { name: 'Visão geral', exact: true }).click();
    assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 1);
    assert.equal(await page.getByLabel('Cenário da demonstração').count(), 1);
  } finally {
    await page.close();
  }
});
test('real students and classes retain the narrow layout', async () => {
  const { page } = await open();
  try {
    for (const view of ['Alunos', 'Turmas']) {
      await page.getByRole('button', { name: view, exact: true }).click();
      await page.getByText('Turma RPC', { exact: true }).first().waitFor();
      for (const width of [420, 600, 1024]) {
        await page.setViewportSize({ width, height: 800 });
        const dimensions = await page.evaluate(() => [
          document.documentElement.clientWidth,
          document.documentElement.scrollWidth,
        ]);
        assert.ok(dimensions[1] <= dimensions[0], `${view}: ${dimensions}`);
      }
    }
  } finally {
    await page.close();
  }
});
