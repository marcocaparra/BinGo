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
async function open(role = 'ADMIN_C', options = {}) {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, { role, ...options });
  await page.goto(url);
  await submitLogin(page);
  await page
    .getByRole('button', {
      name: role === 'ADMIN_C' ? 'Solicitações' : /Pendências/,
      exact: role === 'ADMIN_C',
    })
    .click();
  return { page, fixture };
}
async function fillCreate(page, fixture) {
  await page.getByRole('button', { name: 'Solicitar troca de turma' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Aluno', { exact: true }).selectOption(fixture.students[0].student_id);
  await dialog.getByLabel('Nova turma').selectOption(fixture.classes[1].class_id);
  return dialog;
}
test('C creates with UUIDs and derived source, lists and cancels, retaining history', async () => {
  const { page, fixture } = await open('ADMIN_C', { classRequests: [] });
  try {
    await page.getByRole('heading', { name: 'Nenhuma solicitação registrada' }).waitFor();
    const source = fixture.students[0].class_id;
    const dialog = await fillCreate(page, fixture);
    await dialog.getByRole('button', { name: 'Enviar solicitação' }).click();
    await page.getByText('Solicitação enviada.', { exact: true }).waitFor();
    assert.equal(fixture.students[0].class_id, source);
    const create = fixture.calls.find((c) => c.path.endsWith('/create_class_change_request_v1'));
    assert.match(create.body.p_request_id, /^[0-9a-f-]{36}$/);
    assert.deepEqual(Object.keys(create.body).sort(), [
      'p_destination_class_id',
      'p_request_id',
      'p_student_id',
    ]);
    assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
    assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
    await page
      .locator('app-class-requests app-entity-row')
      .getByRole('button', { name: 'Cancelar' })
      .click();
    await page.getByRole('dialog').getByRole('button', { name: 'Confirmar cancelamento' }).click();
    await page.getByText('Cancelada', { exact: true }).waitFor();
    assert.equal(fixture.students[0].class_id, source);
    assert.equal(await page.getByRole('button', { name: 'Cancelar', exact: true }).count(), 0);
    assert.equal(fixture.classRequests.length, 1);
    assert.equal(
      fixture.calls.find((c) => c.path.endsWith('cancel_class_change_request_v1')).body
        .p_request_id,
      create.body.p_request_id,
    );
  } finally {
    await page.close();
  }
});
test('B approves and refreshes requests and authoritative students/classes', async () => {
  const { page, fixture } = await open('ADMIN_B');
  try {
    await page.getByRole('button', { name: 'Analisar' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Aprovar troca' }).click();
    await page.getByText('Aprovada', { exact: true }).waitFor();
    assert.equal(fixture.students[0].class_id, fixture.classes[1].class_id);
    assert.equal(await page.getByText('Resgates reservados', { exact: true }).count(), 1);
    assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 1);
    await page.getByRole('button', { name: 'Alunos', exact: true }).click();
    await page
      .getByRole('row')
      .filter({ hasText: 'Aluno RPC' })
      .getByText('Turma destino RPC', { exact: true })
      .waitFor();
    assert.ok(fixture.calls.filter((c) => c.path.endsWith('get_admin_students_v1')).length >= 3);
  } finally {
    await page.close();
  }
});
test('B rejects normal requests without changing student class', async () => {
  const { page, fixture } = await open('ADMIN_B');
  try {
    const source = fixture.students[0].class_id;
    await page.getByRole('button', { name: 'Analisar' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Rejeitar' }).click();
    await page.getByText('Rejeitada', { exact: true }).waitFor();
    assert.equal(fixture.students[0].class_id, source);
    assert.equal(await page.getByRole('button', { name: 'Analisar' }).count(), 0);
  } finally {
    await page.close();
  }
});
test('stale blocks approval and still permits rejection', async () => {
  const { page, fixture } = await open('ADMIN_B', {
    students: [
      {
        student_id: '30000000-0000-4000-8000-000000000001',
        name: 'Aluno RPC',
        class_id: '20000000-0000-4000-8000-000000000002',
        status: 'ACTIVE',
        points_student_balance: 800,
      },
    ],
  });
  try {
    await page
      .getByText('A turma atual mudou. Solicitação obsoleta: aprovação bloqueada.', { exact: true })
      .waitFor();
    await page.getByRole('button', { name: 'Analisar' }).click();
    const dialog = page.getByRole('dialog');
    assert.equal(await dialog.getByRole('button', { name: 'Aprovar troca' }).isEnabled(), false);
    assert.equal(await dialog.getByRole('button', { name: 'Rejeitar' }).isEnabled(), true);
    assert.equal(
      fixture.calls.filter((c) => c.path.endsWith('approve_class_change_request_v1')).length,
      0,
    );
    await dialog.getByRole('button', { name: 'Rejeitar' }).click();
    await page.getByText('Rejeitada', { exact: true }).waitFor();
    assert.equal(fixture.students[0].class_id, fixture.classes[1].class_id);
  } finally {
    await page.close();
  }
});
test('a stale conflict arriving after dialog opens reloads state and blocks a second approval', async () => {
  const { page, fixture } = await open('ADMIN_B');
  try {
    await page.getByRole('button', { name: 'Analisar' }).click();
    fixture.students[0].class_id = fixture.classes[1].class_id;
    const dialog = page.getByRole('dialog');
    await dialog.getByRole('button', { name: 'Aprovar troca' }).click();
    await dialog.getByText(/Conflito: a turma atual mudou/).waitFor();
    await dialog.getByText('Turma atual: Turma destino RPC', { exact: true }).waitFor();
    assert.equal(await dialog.getByRole('button', { name: 'Aprovar troca' }).isEnabled(), false);
    assert.equal(fixture.classRequests[0].status, 'PENDING');
    assert.equal(fixture.students[0].class_id, fixture.classes[1].class_id);
  } finally {
    await page.close();
  }
});
test('loading, empty and error states never use requests mocks, and retries recover', async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  const { page, fixture } = await open('ADMIN_C', { requestWait: gate, classRequests: [] });
  try {
    await page.getByRole('heading', { name: 'Carregando solicitações…' }).waitFor();
    release();
    await page.getByRole('heading', { name: 'Nenhuma solicitação registrada' }).waitFor();
    fixture.requestError = true;
    await page.getByRole('button', { name: 'Alunos', exact: true }).click();
    await page.getByRole('button', { name: 'Solicitações', exact: true }).click();
    await page.getByRole('heading', { name: 'Não foi possível carregar solicitações' }).waitFor();
    assert.equal(await page.getByText(/TT-032|Marina Santos/).count(), 0);
    assert.equal(await page.locator('app-class-requests app-entity-row').count(), 0);
    fixture.requestError = false;
    await page.getByRole('button', { name: 'Tentar novamente' }).click();
    await page.getByRole('heading', { name: 'Nenhuma solicitação registrada' }).waitFor();
  } finally {
    release();
    await page.close();
  }
});
test('submitting disables duplicate sends; a lost create response retries the same UUID and payload', async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  const { page, fixture } = await open('ADMIN_C', {
    classRequests: [],
    requestMutationWait: gate,
    loseCreateResponse: true,
  });
  try {
    const dialog = await fillCreate(page, fixture);
    await dialog.getByRole('button', { name: 'Enviar solicitação' }).click();
    await dialog.getByRole('button', { name: 'Enviando…' }).waitFor();
    assert.equal(await dialog.getByRole('button', { name: 'Enviando…' }).isEnabled(), false);
    release();
    await dialog.getByText(/Não foi possível concluir/).waitFor();
    await dialog.getByRole('button', { name: 'Enviar solicitação' }).click();
    await page.getByText('Solicitação enviada.', { exact: true }).waitFor();
    const calls = fixture.calls.filter((c) => c.path.endsWith('/create_class_change_request_v1'));
    assert.ok(calls.length >= 2);
    assert.deepEqual(calls.at(-1).body, calls[0].body);
    assert.equal(fixture.classRequests.length, 1);
  } finally {
    release();
    await page.close();
  }
});
