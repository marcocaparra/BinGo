const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { installSupabaseFixture, submitLogin, schoolId } = require('./test/supabase-fixture.cjs');

let browser;
before(async () => {
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.BINGO_BROWSER_PATH ||
      'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  });
});
after(async () => browser?.close());

async function open(options = {}) {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, options);
  await page.goto(process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/');
  await submitLogin(page);
  await page.getByRole('button', { name: 'Descartes', exact: true }).click();
  return { page, fixture };
}

const otherSchool = '10000000-0000-4000-8000-000000000002';
const rows = [
  {
    deposit_id: 'deposit-valid-identified',
    event_id: 'event-1',
    school_id: schoolId,
    school_name: 'Escola Norte RPC',
    machine_id: 'machine-1',
    machine_name: 'Totem Norte RPC',
    class_id: 'class-1',
    class_name: '9A RPC',
    student_id: 'student-1',
    student_name: 'Aluno Identificado RPC',
    is_valid: true,
    detected_type: 'BATTERY',
    waste_category_code: 'BATTERY',
    category_source: 'AI_CONFIRMED',
    bonus_rate_applied: 1,
    bonus_bincoins_awarded: 800,
    points_awarded_student: 1600,
    points_awarded_class: 1900,
    created_at: '2026-10-01T12:00:00Z',
  },
  {
    deposit_id: 'deposit-valid-anonymous',
    event_id: 'event-2',
    school_id: schoolId,
    school_name: 'Escola Norte RPC',
    machine_id: 'machine-1',
    machine_name: 'Totem Norte RPC',
    class_id: 'class-1',
    class_name: '9A RPC',
    student_id: null,
    student_name: null,
    is_valid: true,
    detected_type: null,
    waste_category_code: 'UNKNOWN',
    category_source: 'UNIDENTIFIED',
    bonus_rate_applied: 0,
    bonus_bincoins_awarded: 0,
    points_awarded_student: 0,
    points_awarded_class: 1900,
    created_at: '2026-10-01T11:00:00Z',
  },
  {
    deposit_id: 'deposit-invalid-other-school',
    event_id: 'event-3',
    school_id: otherSchool,
    school_name: 'Escola Sul RPC',
    machine_id: 'machine-2',
    machine_name: 'Totem Sul RPC',
    class_id: 'class-2',
    class_name: '8B RPC',
    student_id: null,
    student_name: null,
    is_valid: false,
    detected_type: 'UNSUPPORTED',
    waste_category_code: null,
    category_source: null,
    bonus_rate_applied: 0,
    bonus_bincoins_awarded: 0,
    points_awarded_student: 0,
    points_awarded_class: 0,
    created_at: '2026-10-01T10:00:00Z',
  },
];

for (const role of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C'])
  test(`${role} reads real deposits in its approved scope`, async () => {
    const { page, fixture } = await open({ role, deposits: rows });
    try {
      await page.getByText('Aluno Identificado RPC', { exact: true }).waitFor();
      assert.equal(await page.locator('app-deposits tbody tr').count(), role === 'ADMIN_A' ? 3 : 2);
      await page.getByText('Sem identificação', { exact: true }).first().waitFor();
      await page.getByText('IA confirmada', { exact: true }).waitFor();
      await page.getByText('Não identificada', { exact: true }).waitFor();
      await page.getByText('Válido', { exact: true }).first().waitFor();
      if (role === 'ADMIN_A') {
        await page.getByText('Escola Sul RPC', { exact: true }).waitFor();
        await page.getByText('Inválido', { exact: true }).waitFor();
        await page.getByText('Sem categoria', { exact: true }).waitFor();
      } else {
        assert.equal(await page.getByText('Escola Sul RPC', { exact: true }).count(), 0);
        assert.equal(await page.getByRole('columnheader', { name: 'Escola' }).count(), 0);
      }
      const text = await page.locator('app-deposits').innerText();
      for (const mock of [
        'Ana Clara M.',
        'Lucas P.',
        'Marina S.',
        'Total registrado',
        'Nesta semana',
        'Em revisão',
        '1284',
        '184',
      ])
        assert.ok(!text.includes(mock), mock);
      assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
      assert.deepEqual(
        fixture.calls.filter((c) => c.path.endsWith('get_admin_deposits_v1')).map((c) => c.body),
        [{}],
      );
      for (const width of [420, 1024]) {
        await page.setViewportSize({ width, height: 800 });
        assert.ok(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
          ),
        );
      }
    } finally {
      await page.close();
    }
  });

test('loading, empty, error, retry and refetch never fall back to discarded mocks', async () => {
  let release;
  const wait = new Promise((resolve) => (release = resolve));
  const { page, fixture } = await open({ role: 'ADMIN_B', deposits: [], depositsWait: wait });
  try {
    await page.getByRole('heading', { name: 'Carregando descartes', exact: true }).waitFor();
    assert.equal(await page.locator('app-deposits tbody tr').count(), 0);
    release();
    fixture.depositsWait = null;
    await page.getByRole('heading', { name: 'Nenhum descarte', exact: true }).waitFor();
    fixture.depositsError = true;
    await page.getByRole('button', { name: 'Atualizar descartes', exact: true }).click();
    await page
      .getByRole('heading', { name: 'Não foi possível carregar descartes', exact: true })
      .waitFor();
    fixture.depositsError = false;
    fixture.deposits = rows;
    await page.getByRole('button', { name: 'Tentar novamente', exact: true }).click();
    await page.getByText('Aluno Identificado RPC', { exact: true }).waitFor();
    fixture.deposits = [{ ...rows[0], student_name: 'Fotografia atualizada RPC' }];
    await page.getByRole('button', { name: 'Atualizar descartes', exact: true }).click();
    await page.getByText('Fotografia atualizada RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('Aluno Identificado RPC', { exact: true }).count(), 0);
  } finally {
    release();
    await page.close();
  }
});

test('logout and session change discard a late deposits response', async () => {
  let release;
  const wait = new Promise((resolve) => (release = resolve));
  let started;
  const read = new Promise((resolve) => (started = resolve));
  const { page, fixture } = await open({
    role: 'ADMIN_A',
    deposits: rows,
    depositsWait: wait,
    onDepositRead: started,
  });
  try {
    await read;
    await page.getByRole('button', { name: 'Sair', exact: true }).click();
    await page.getByRole('button', { name: 'Acessar o Admin', exact: true }).waitFor();
    fixture.role = 'ADMIN_C';
    fixture.schoolId = otherSchool;
    fixture.depositsWait = null;
    await submitLogin(page);
    await page.getByRole('button', { name: 'Descartes', exact: true }).click();
    await page.getByText('Totem Sul RPC', { exact: true }).waitFor();
    const late = page.waitForResponse((response) =>
      response.url().endsWith('/rpc/get_admin_deposits_v1'),
    );
    release();
    await late;
    assert.equal(await page.locator('app-deposits tbody tr').count(), 1);
    assert.equal(await page.getByText('Aluno Identificado RPC', { exact: true }).count(), 0);
  } finally {
    release();
    await page.close();
  }
});
