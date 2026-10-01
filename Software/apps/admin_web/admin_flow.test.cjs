const { test } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { installSupabaseFixture, submitLogin } = require('./test/supabase-fixture.cjs');

const url = process.env.BINGO_ADMIN_URL || 'http://127.0.0.1:8106/';
const browserOptions = {
  headless: true,
  executablePath:
    process.env.BINGO_BROWSER_PATH ||
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
};

async function openAdmin(page, role = 'ADMIN_C') {
  await installSupabaseFixture(page, { role });
  await page.goto(url);
  await submitLogin(page);
  const heading =
    role === 'ADMIN_A'
      ? 'Visão global do BinGo'
      : role === 'ADMIN_B'
        ? 'Gestão da escola'
        : 'Operação da escola';
  await page.getByRole('heading', { name: heading }).waitFor();
}

async function assertNoHorizontalOverflow(page) {
  const dimensions = await page.evaluate(() => ({
    viewport: document.documentElement.clientWidth,
    content: document.documentElement.scrollWidth,
  }));
  assert.ok(
    dimensions.content <= dimensions.viewport,
    `overflow horizontal: ${dimensions.content}px em ${dimensions.viewport}px`,
  );
}

test('authenticated access opens the real operational overview', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await openAdmin(page);
    await page.locator('app-overview').getByText('Snapshot RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('Dados demonstrativos', { exact: true }).count(), 0);
    assert.equal(await page.getByText('1.284', { exact: true }).count(), 0);
    assert.equal(await page.getByText('32 hoje · 184 nesta semana', { exact: true }).count(), 0);
  } finally {
    await browser.close();
  }
});

test('primary views and demonstrative states are navigable', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
    await openAdmin(page);

    await page.getByRole('button', { name: 'Descartes', exact: true }).click();
    await page.getByRole('heading', { name: 'Descartes recentes' }).waitFor();
    assert.equal(await page.getByRole('columnheader', { name: 'Aluno ou perfil' }).count(), 1);

    await page.getByRole('button', { name: /Solicitações de ajuda/ }).click();
    await page.getByRole('heading', { name: 'Solicitações de ajuda' }).waitFor();
    await page.getByRole('button', { name: 'Assumir' }).click();
    await page.getByText(/marcado em atendimento/).waitFor();

    await page.getByRole('button', { name: /Resgates/ }).click();
    await page.getByRole('heading', { name: 'Resgates pendentes' }).waitFor();
    await page.getByRole('button', { name: 'Validar entrega' }).first().click();
    await page.getByRole('dialog').getByRole('button', { name: 'Confirmar entrega' }).click();
    await page.getByText(/Resgate entregue/).waitFor();

    await page.getByRole('button', { name: 'Totens' }).click();
    await page.getByRole('heading', { name: 'Estado dos Totens' }).waitFor();
    await page.getByText('Totem RPC', { exact: true }).waitFor();
    assert.equal(await page.getByText('ONLINE', { exact: true }).count(), 1);
    assert.equal(await page.locator('.last-seen').count(), 1);
    await page.getByText('Não registrada', { exact: true }).waitFor();
    assert.equal(await page.getByLabel('Cenário da demonstração').count(), 0);
    // Cenários demo continuam isolados na tela de Descartes.
    await page.getByRole('button', { name: 'Descartes', exact: true }).click();
    await page.getByLabel('Cenário da demonstração').selectOption('error');
    await page.getByRole('heading', { name: 'Não foi possível atualizar' }).waitFor();
    await page.getByRole('button', { name: 'Tentar novamente' }).click();
    await page.getByText(/carregados novamente/).waitFor();
  } finally {
    await browser.close();
  }
});

test('admin stays contained at school tablet and narrow widths', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    for (const viewport of [
      { width: 420, height: 720 },
      { width: 480, height: 800 },
      { width: 600, height: 1024 },
    ]) {
      const page = await browser.newPage({ viewport });
      await page.goto(url);
      await assertNoHorizontalOverflow(page);
      await openAdmin(page);
      await assertNoHorizontalOverflow(page);

      for (const name of ['Descartes', /Solicitações de ajuda/, /Resgates/, 'Totens']) {
        await page.getByRole('button', { name, exact: typeof name === 'string' }).click();
        await assertNoHorizontalOverflow(page);
      }
      await page.close();
    }
  } finally {
    await browser.close();
  }
});

test('roles expose only the areas and actions allowed by the functional contract', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const globalPage = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await openAdmin(globalPage, 'ADMIN_A');
    assert.equal(await globalPage.getByRole('button', { name: 'Escolas', exact: true }).count(), 1);
    assert.equal(await globalPage.getByRole('button', { name: /Resgates/ }).count(), 0);
    assert.equal(
      await globalPage.getByRole('button', { name: /Solicitações de ajuda/ }).count(),
      0,
    );
    await globalPage.getByRole('button', { name: 'Economia', exact: true }).click();
    await globalPage.getByRole('heading', { name: 'Configurações econômicas' }).waitFor();
    await globalPage.close();

    const schoolPage = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await openAdmin(schoolPage, 'ADMIN_B');
    await schoolPage.getByRole('button', { name: 'Alunos', exact: true }).click();
    await schoolPage.getByRole('button', { name: 'Editar' }).first().waitFor();
    assert.ok((await schoolPage.getByRole('button', { name: 'Editar' }).count()) > 0);
    await schoolPage.getByRole('button', { name: /Pendências/ }).click();
    await schoolPage.getByRole('heading', { name: 'Pendências da escola' }).waitFor();
    await schoolPage.close();

    const operatorPage = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await openAdmin(operatorPage, 'ADMIN_C');
    await operatorPage.getByRole('button', { name: 'Alunos', exact: true }).click();
    await operatorPage.getByRole('button', { name: 'Consultar' }).first().waitFor();
    assert.equal(await operatorPage.getByRole('button', { name: 'Editar' }).count(), 0);
    assert.ok((await operatorPage.getByRole('button', { name: 'Consultar' }).count()) > 0);
    assert.equal(
      await operatorPage.getByRole('button', { name: 'Turmas', exact: true }).count(),
      0,
    );
    assert.equal(
      await operatorPage.getByRole('button', { name: 'Administradores', exact: true }).count(),
      0,
    );
    await operatorPage.close();
  } finally {
    await browser.close();
  }
});

test('school RPC creation and the remaining demonstrative actions stay isolated', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const manager = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await openAdmin(manager, 'ADMIN_B');

    await manager.getByRole('button', { name: 'Alunos', exact: true }).click();
    await manager.getByRole('button', { name: 'Cadastrar aluno' }).click();
    const studentDialog = manager.getByRole('dialog');
    await studentDialog.getByLabel('Nome completo').fill('João Demo');
    await studentDialog.getByLabel('E-mail institucional').fill('joao@aluno.demo');
    await studentDialog.getByLabel('RA ou matrícula').fill('20261999');
    await studentDialog
      .getByLabel('Turma', { exact: true })
      .selectOption('20000000-0000-4000-8000-000000000001');
    await studentDialog.getByRole('button', { name: 'Cadastrar aluno' }).click();
    await manager.getByText('João Demo', { exact: true }).waitFor();

    await manager.getByRole('button', { name: /Pendências/ }).click();
    await manager.getByRole('button', { name: 'Analisar' }).click();
    await manager.getByRole('dialog').getByRole('button', { name: 'Aprovar troca' }).click();
    await manager.getByText('Aprovada', { exact: true }).first().waitFor();

    await manager.getByRole('button', { name: /Resgates/ }).click();
    await manager.getByRole('button', { name: 'Cancelar' }).first().click();
    await manager.getByRole('dialog').getByRole('button', { name: 'Cancelar resgate' }).click();
    await manager.getByText(/Resgate cancelado/).waitFor();
    await manager.close();

    const operator = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await openAdmin(operator, 'ADMIN_C');
    await operator.getByRole('button', { name: 'Solicitações', exact: true }).click();
    await operator.getByRole('button', { name: 'Solicitar troca de turma' }).click();
    await operator
      .getByRole('dialog')
      .getByLabel('Aluno', { exact: true })
      .selectOption('30000000-0000-4000-8000-000000000001');
    await operator
      .getByRole('dialog')
      .getByLabel('Nova turma')
      .selectOption('20000000-0000-4000-8000-000000000002');
    await operator.getByRole('dialog').getByRole('button', { name: 'Enviar solicitação' }).click();
    await operator.getByText('Solicitação enviada.', { exact: true }).waitFor();

    await operator.getByRole('button', { name: 'Produtos e estoque', exact: true }).click();
    await operator.getByRole('button', { name: 'Editar' }).first().click();
    const productDialog = operator.getByRole('dialog');
    await productDialog.getByLabel('Estoque').fill('21');
    await productDialog.getByRole('button', { name: 'Salvar alterações' }).click();
    await operator.getByText('21 unidades', { exact: true }).waitFor();
  } finally {
    await browser.close();
  }
});

test('global administrator can prepare schools, missions and economy without school queues', async () => {
  const browser = await chromium.launch(browserOptions);
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await openAdmin(page, 'ADMIN_A');

    await page.getByRole('button', { name: 'Escolas', exact: true }).click();
    await page.getByRole('button', { name: 'Cadastrar escola' }).click();
    const schoolDialog = page.getByRole('dialog');
    await schoolDialog.getByLabel('Nome da escola').fill('Escola Demo');
    assert.equal(await schoolDialog.getByLabel('Cidade e estado').count(), 0);
    assert.equal(await schoolDialog.getByLabel('Estado', { exact: true }).count(), 0);
    await schoolDialog.getByRole('button', { name: 'Cadastrar escola' }).click();
    await page.getByText('Escola Demo', { exact: true }).waitFor();

    await page.getByRole('button', { name: 'Missões', exact: true }).click();
    await page.getByRole('button', { name: 'Criar missão global' }).click();
    const missionDialog = page.getByRole('dialog');
    await missionDialog.getByLabel('Nome da missão').fill('Rota responsável');
    await missionDialog.getByRole('button', { name: 'Criar missão' }).click();
    await page.getByText('Rota responsável', { exact: true }).waitFor();

    await page.getByRole('button', { name: 'Economia', exact: true }).click();
    await page.getByRole('button', { name: 'Editar' }).first().click();
    const economyDialog = page.getByRole('dialog');
    await economyDialog.getByLabel('Valor em pontos').fill('35');
    await economyDialog.getByRole('button', { name: 'Salvar regra' }).click();
    await page.getByText('35 pontos', { exact: true }).waitFor();

    await page.getByRole('button', { name: 'Totens', exact: true }).click();
    await page.getByText('Totem RPC', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Ver diagnóstico' }).count(), 0);
    await page.getByText('Não registrada', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: /Resgates/ }).count(), 0);
  } finally {
    await browser.close();
  }
});
