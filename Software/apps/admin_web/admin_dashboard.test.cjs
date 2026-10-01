const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { installSupabaseFixture, submitLogin, schoolId } = require('./test/supabase-fixture.cjs');
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
async function open(options = {}) {
  const page = await browser.newPage();
  const fixture = await installSupabaseFixture(page, options);
  await page.goto(url);
  await submitLogin(page);
  await page.locator('app-overview').waitFor();
  return { page, fixture };
}
async function loaded(page) {
  await page.waitForFunction(() => {
    const b = Array.from(document.querySelectorAll('app-overview button')).find((x) =>
      x.textContent.includes('Atualizar visão geral'),
    );
    return b && !b.disabled;
  });
}
async function card(page, label, value, note) {
  const c = page
    .locator('app-overview app-summary-card')
    .filter({ has: page.locator('small', { hasText: new RegExp('^' + label + '$') }) });
  assert.equal(await c.locator('strong').innerText(), value, label);
  if (note) assert.ok((await c.innerText()).includes(note));
}
async function noDemo(page) {
  const text = await page.locator('app-overview').innerText();
  for (const fragment of [
    'Colégio ENIAC',
    'Horizonte',
    'AJ-104',
    'TT-032',
    '1.284',
    'Totem',
    'participação',
    'Guarulhos',
    'implantação',
    'SCR4P',
    'Descartes validados',
    'Ajudas abertas',
  ])
    assert.ok(!text.includes(fragment), fragment);
  assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
  assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
}
test('A derives global school/admin totals, structural machines, real cap and reads only once', async () => {
  const { page, fixture } = await open({
    role: 'ADMIN_A',
    priceCap: 1700,
    managedSchools: [
      {
        school_id: 's1',
        name: 'Escola Norte real',
        student_count: 7,
        class_count: 2,
        admin_count: 3,
        machine_count: 2,
      },
      {
        school_id: 's2',
        name: 'Escola Sul real',
        student_count: 11,
        class_count: 4,
        admin_count: 2,
        machine_count: 5,
      },
      {
        school_id: 's3',
        name: 'Escola vazia real',
        student_count: 0,
        class_count: 0,
        admin_count: 0,
        machine_count: 0,
      },
    ],
    managedAdmins: Array.from({ length: 5 }, (_, i) => ({
      admin_id: 'a' + i,
      name: 'Conta ' + i,
      email: 'a' + i + '@example.test',
      role: i ? 'ADMIN_C' : 'ADMIN_A',
      school_id: i ? 's1' : null,
      school_name: i ? 'Escola Norte real' : null,
      status: i < 3 ? 'ACTIVE' : 'INACTIVE',
      access_linked: i < 3,
    })),
  });
  try {
    await loaded(page);
    await card(page, 'Escolas cadastradas', '3');
    await card(page, 'Alunos cadastrados', '18');
    await card(page, 'Máquinas cadastradas', '7', 'não indica disponibilidade');
    await card(page, 'Administradores', '5', '3 ACTIVE · 2 INACTIVE');
    await card(page, 'Sem vínculo de acesso', '2');
    await card(page, 'Teto do BinBazar', '1.700');
    assert.equal(
      await page.locator('app-overview').getByText('11 alunos · 4 turmas', { exact: true }).count(),
      1,
    );
    const reads = fixture.calls.filter(
      (c) => c.path.includes('/rpc/') && !c.path.endsWith('get_my_admin_context_v1'),
    );
    assert.deepEqual(
      reads.map((c) => c.path.split('/').at(-1)).sort(),
      ['get_admin_schools_v1', 'get_managed_admins_v1', 'get_binbazar_price_cap_v1'].sort(),
    );
    reads.forEach((c) => assert.deepEqual(c.body, {}));
    await noDemo(page);
  } finally {
    await page.close();
  }
});
for (const role of ['ADMIN_B', 'ADMIN_C'])
  test(`${role} composes school students/classes, scoped requests, pending snapshots and zero finite stock`, async () => {
    const { page, fixture } = await open({ role, priceCap: 2200 });
    try {
      await loaded(page);
      fixture.students.push(
        { ...fixture.students[0], student_id: 's-inactive', status: 'INACTIVE' },
        { ...fixture.students[0], student_id: 's-active', status: 'ACTIVE' },
      );
      fixture.managedAdmins.push(
        { ...fixture.managedAdmins[1], admin_id: 'c-inactive', status: 'INACTIVE' },
        { ...fixture.managedAdmins[1], admin_id: 'foreign-c', school_id: 'foreign-school' },
      );
      const req = fixture.classRequests[0];
      fixture.classRequests.push(
        {
          ...req,
          request_id: 'foreign-author',
          student_name: 'Pedido de outro C',
          requested_by_admin_id: 'other-c',
          created_at: '2026-10-01T12:00:00Z',
        },
        { ...req, request_id: 'finished', student_name: 'Pedido concluído', status: 'APPROVED' },
      );
      fixture.redemptions.push(
        {
          ...fixture.redemptions[0],
          redemption_id: 'pending-2',
          code: 'BGO-SECOND',
          reward_name_snapshot: 'Snapshot mais recente',
          created_at: '2026-10-01T14:00:00Z',
        },
        {
          ...fixture.redemptions[0],
          redemption_id: 'delivered',
          status: 'DELIVERED',
          reward_name_snapshot: 'Já entregue',
        },
        {
          ...fixture.redemptions[0],
          redemption_id: 'canceled',
          status: 'CANCELED',
          reward_name_snapshot: 'Já cancelado',
        },
      );
      fixture.products.push(
        { ...fixture.products[0], reward_id: 'zero', name: 'Esgotado real', stock_qty: 0 },
        {
          ...fixture.products[0],
          reward_id: 'unlimited',
          name: 'Ilimitado ativo',
          stock_qty: null,
        },
        {
          ...fixture.products[0],
          reward_id: 'inactive-zero',
          name: 'Inativo zero',
          is_active: false,
          stock_qty: 0,
        },
      );
      await page.getByRole('button', { name: 'Atualizar visão geral' }).click();
      await loaded(page);
      await card(page, 'Alunos ACTIVE', '2', '1 INACTIVE');
      await card(page, 'Turmas disponíveis', '2');
      await card(page, 'Resgates PENDING', '2');
      await card(page, 'Produtos ativos', '3', '1 ativos sem estoque');
      await card(page, 'Teto do BinBazar', '2.200');
      await card(
        page,
        role === 'ADMIN_B' ? 'Trocas PENDING' : 'Minhas solicitações PENDING',
        role === 'ADMIN_B' ? '2' : '1',
      );
      if (role === 'ADMIN_B') await card(page, 'Administradores C', '2', '1 ACTIVE · 1 INACTIVE');
      else {
        assert.equal(
          await page
            .locator('app-overview')
            .getByText('Pedido de outro C', { exact: true })
            .count(),
          0,
        );
        assert.equal(
          fixture.calls.some((c) => c.path.endsWith('get_managed_admins_v1')),
          false,
        );
      }
      assert.equal(
        await page
          .locator('app-overview')
          .getByText('Snapshot mais recente', { exact: true })
          .count(),
        1,
      );
      assert.equal(
        await page.locator('app-overview').getByText('Esgotado real', { exact: true }).count(),
        1,
      );
      for (const name of ['Já entregue', 'Já cancelado', 'Pedido concluído', 'Inativo zero'])
        assert.equal(
          await page.locator('app-overview').getByText(name, { exact: true }).count(),
          0,
        );
      const titles = await page.locator('app-overview app-entity-row strong').allTextContents();
      assert.ok(titles.indexOf('Snapshot mais recente') < titles.indexOf('Snapshot RPC'));
      assert.equal(
        await page.locator('app-overview').getByText('1900 XP', { exact: true }).count(),
        1,
      );
      for (const rpc of [
        'get_admin_students_v1',
        'get_admin_classes_v1',
        'get_class_change_requests_v1',
        'get_admin_binbazar_products_v1',
        'get_admin_redemptions_v1',
        'get_binbazar_price_cap_v1',
      ])
        assert.equal(fixture.calls.filter((c) => c.path.endsWith(rpc)).length, 2, rpc);
      await noDemo(page);
    } finally {
      await page.close();
    }
  });
for (const role of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C'])
  test(`${role} loading never shows invented zeros, then exposes authoritative empty and NULL cap`, async () => {
    let release;
    const gate = new Promise((r) => {
      release = r;
    });
    const { page } = await open({
      role,
      structureWait: gate,
      requestWait: gate,
      schoolWait: gate,
      binbazarWait: gate,
      capWait: gate,
      managedSchools: [],
      managedAdmins: [],
      students: [],
      classes: [],
      classRequests: [],
      products: [],
      redemptions: [],
    });
    try {
      await page.getByText('Carregando fotografia atual…', { exact: true }).waitFor();
      const initial = await page.locator('app-overview app-summary-card strong').allTextContents();
      assert.ok(initial.every((x) => x === '…'));
      assert.equal(await page.getByText('Não configurado', { exact: true }).count(), 0);
      release();
      await loaded(page);
      const final = await page.locator('app-overview app-summary-card strong').allTextContents();
      assert.ok(final.every((x) => x === '0' || x === 'Não configurado'));
      await card(page, 'Teto do BinBazar', 'Não configurado');
      await noDemo(page);
    } finally {
      release();
      await page.close();
    }
  });
test('partial school failures retain healthy metrics and retry reads real data', async () => {
  const { page, fixture } = await open({ role: 'ADMIN_B', binbazarError: true, priceCap: 1800 });
  try {
    await loaded(page);
    await card(page, 'Alunos ACTIVE', '1');
    await card(page, 'Produtos ativos', 'Indisponível');
    await card(page, 'Resgates PENDING', 'Indisponível');
    await card(page, 'Teto do BinBazar', '1.800');
    await page.getByRole('alert').waitFor();
    assert.equal(
      await page.locator('app-overview').getByText('Snapshot RPC', { exact: true }).count(),
      0,
    );
    fixture.binbazarError = false;
    await page.getByRole('button', { name: 'Atualizar visão geral' }).click();
    await loaded(page);
    await card(page, 'Resgates PENDING', '1');
    assert.equal(await page.getByRole('alert').count(), 0);
    await noDemo(page);
  } finally {
    await page.close();
  }
});
for (const role of ['ADMIN_A', 'ADMIN_C'])
  test(`${role} total error has unavailable metrics, no fallback and allows retry`, async () => {
    const { page, fixture } = await open({
      role,
      structureError: true,
      schoolError: true,
      requestError: true,
      binbazarError: true,
      capError: true,
    });
    try {
      await loaded(page);
      assert.ok(
        (await page.locator('app-overview app-summary-card strong').allTextContents()).every(
          (x) => x === 'Indisponível',
        ),
      );
      await noDemo(page);
      fixture.structureError =
        fixture.schoolError =
        fixture.requestError =
        fixture.binbazarError =
        fixture.capError =
          false;
      await page.getByRole('button', { name: 'Atualizar visão geral' }).click();
      await loaded(page);
      await card(page, 'Teto do BinBazar', 'Não configurado');
    } finally {
      await page.close();
    }
  });
test('logout invalidates slow A reads; C login, backend role/school refresh and mutations return fresh snapshots', async () => {
  let release;
  const gate = new Promise((r) => {
    release = r;
  });
  const { page, fixture } = await open({ role: 'ADMIN_A', structureWait: gate });
  try {
    await page.getByRole('button', { name: 'Sair', exact: true }).click();
    await page.getByLabel('Senha', { exact: true }).waitFor();
    fixture.role = 'ADMIN_C';
    await submitLogin(page);
    await loaded(page);
    await card(page, 'Alunos ACTIVE', '1');
    const oldResponse = page.waitForResponse((r) => r.url().endsWith('/rpc/get_admin_schools_v1'));
    release();
    await oldResponse;
    await noDemo(page);
    assert.equal(
      await page
        .locator('app-overview')
        .getByText('Escola estrutural RPC', { exact: true })
        .count(),
      0,
    );
    fixture.structureWait = null;
    fixture.role = 'ADMIN_B';
    fixture.schoolId = '10000000-0000-4000-8000-000000000002';
    fixture.students = [];
    fixture.classes = [];
    fixture.classRequests = [];
    fixture.products = [];
    fixture.redemptions = [];
    await page.reload();
    await loaded(page);
    await card(page, 'Alunos ACTIVE', '0');
    await card(page, 'Administradores C', '0');
    assert.equal(
      await page.locator('app-overview').getByText('Snapshot RPC', { exact: true }).count(),
      0,
    );
    fixture.students = [
      { student_id: 'fresh', name: 'Novo contexto', class_id: 'freshclass', status: 'ACTIVE' },
    ];
    await page.getByRole('button', { name: 'Ver alunos', exact: true }).click();
    await page.getByText('Novo contexto', { exact: true }).waitFor();
    await page.getByRole('button', { name: 'Visão geral', exact: true }).click();
    await loaded(page);
    await card(page, 'Alunos ACTIVE', '1');
  } finally {
    release();
    await page.close();
  }
});
for (const role of ['ADMIN_A', 'ADMIN_B', 'ADMIN_C'])
  test(`${role} shortcuts navigate real views and dashboard remains contained at narrow widths`, async () => {
    const { page, fixture } = await open({ role });
    try {
      await loaded(page);
      for (const width of [420, 600, 1024]) {
        await page.setViewportSize({ width, height: 800 });
        const d = await page.evaluate(() => [
          document.documentElement.clientWidth,
          document.documentElement.scrollWidth,
        ]);
        assert.ok(d[1] <= d[0], `${role} overflow at ${width}`);
      }
      const links =
        role === 'ADMIN_A'
          ? [
              ['Ver escolas', 'app-schools'],
              ['Ver administradores', 'app-administrators'],
              ['Ver economia', 'app-economy'],
            ]
          : [
              [
                role === 'ADMIN_B' ? 'Ver pendências' : 'Ver minhas solicitações',
                role === 'ADMIN_B' ? 'app-pending' : 'app-requests',
              ],
              ['Ver resgates', 'app-redemptions'],
              ['Ver produtos', 'app-products'],
              ['Ver alunos', 'app-students'],
            ];
      for (const [name, selector] of links) {
        await page.getByRole('button', { name, exact: true }).click();
        await page.locator(selector).waitFor();
        await page.getByRole('button', { name: 'Visão geral', exact: true }).click();
        await loaded(page);
      }
      assert.ok(
        fixture.calls
          .filter((c) => c.path.includes('/rpc/'))
          .every((c) => c.path.split('/').at(-1).startsWith('get_')),
      );
    } finally {
      await page.close();
    }
  });
