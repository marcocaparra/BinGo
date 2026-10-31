const { test } = require('node:test');
const assert = require('node:assert/strict');
const { DevApi } = require('../local_api.js');
const { schoolLabels } = require('../local_api.js');

test('Rótulos escolares preservam valores e usam somente anos da etapa retornados pelo contexto', () => {
  const classes = [
    ...['1', '2º Ano', '3_ANO'].map(grade => ({ segment: 'ENSINO_MEDIO', grade })),
    ...['6', '7° ANO', '8', '9'].map(grade => ({ segment: 'FUNDAMENTAL_2', grade })),
  ];
  const before = JSON.stringify(classes);
  const medium = schoolLabels(classes, 'ENSINO_MEDIO');
  assert.deepEqual(medium.segments, [{ id: 'ENSINO_MEDIO', name: 'ENSINO MÉDIO' }, { id: 'FUNDAMENTAL_2', name: 'ENSINO FUNDAMENTAL 2' }]);
  assert.deepEqual(medium.grades, [{ id: '1', name: '1° ANO' }, { id: '2º Ano', name: '2° ANO' }, { id: '3_ANO', name: '3° ANO' }]);
  assert.deepEqual(schoolLabels(classes, 'FUNDAMENTAL_2').grades.map(row => row.name), ['6° ANO', '7° ANO', '8° ANO', '9° ANO']);
  assert.deepEqual(schoolLabels(classes.slice(0, 1), 'ENSINO_MEDIO').grades, [{ id: '1', name: '1° ANO' }]);
  assert.deepEqual(schoolLabels([], 'ENSINO_MEDIO').grades, []);
  assert.equal(schoolLabels([{ segment: 'OUTRO', grade: 'especial' }], 'OUTRO').grades[0].name, 'especial');
  assert.equal(JSON.stringify(classes), before);
});
const ids = [1, 2, 3, 4, 5].map(i => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`);
const [event, machine, school, classId, student] = ids;
const response = (data, status = 200, headers = {}) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...headers } });
const context = { school: { id: school, name: 'Escola' }, machine: { id: machine, name: 'Totem' }, classes: [{ id: classId, name: 'Turma', segment: null, grade: null }], students: [{ id: student, name: 'Aluno', class_id: classId, status: 'ACTIVE' }] };
const base = { source: 'SIMULATED', session: { event_id: event, state: 'IDENTIFYING', mode: 'student', class_id: classId, student_id: null, receipt: null }, identity: null, commands: [], allowed_actions: ['identify', 'cancel'] };
const bound = { ...base, session: { ...base.session, state: 'SAFETY', student_id: student, student_name: 'Aluno', class_name: 'Turma' }, identity: { event_id: event, machine_id: machine, school_id: school, class_id: classId, student_id: student, project_ref: 'synthetic', source: 'SUPABASE_DEV_PIN_V1', validated_at: '2026-10-30T12:00:00Z' }, allowed_actions: ['safety', 'cancel'] };

test('Perfil DEV depende do marcador local, não de query ou readiness físico', async () => {
  const calls = [];
  const api = new DevApi(async (path, options) => { calls.push(path); assert.equal(options.method, 'GET'); return response({ status: 'ok' }, 200, { 'X-Totem-Runtime': 'dev-integration' }); });
  assert.equal(await api.isDev(), true); assert.deepEqual(calls, ['/health']);
  assert.equal(await new DevApi(async () => response({ status: 'ok' })).isDev(), false);
});
test('Health DEV exige procedência simulada e economia bloqueada', async () => {
  const data = { central: 'AVAILABLE', scope: 'SUPABASE_DEV_READ_ONLY', mechanical_source: 'SIMULATED', economic_registration: false };
  await new DevApi(async () => response(data)).health();
  for (const change of [{ economic_registration: true }, { mechanical_source: 'PHYSICAL' }, { central: 'UNAVAILABLE' }]) {
    await assert.rejects(() => new DevApi(async () => response({ ...data, ...change })).health(), e => e.code === 'INVALID_RESPONSE');
  }
});
test('Contexto valida turma/aluno, duplicação e referências; vazio é explícito', async () => {
  assert.deepEqual(await new DevApi(async () => response(context)).context(), context);
  await new DevApi(async () => response({ ...context, classes: [], students: [] })).context();
  for (const invalid of [{ ...context, classes: [null] }, { ...context, students: [null] }, { ...context, classes: [...context.classes, ...context.classes] }, { ...context, students: [{ ...context.students[0], class_id: event }] }, { ...context, students: [{ ...context.students[0], status: 'INACTIVE' }] }]) {
    await assert.rejects(() => new DevApi(async () => response(invalid)).context(), e => e.code === 'INVALID_RESPONSE');
  }
});
test('Início e replay usam somente o mesmo command_id', async () => {
  const bodies = [];
  const api = new DevApi(async (path, options) => { assert.equal(path, '/local/simulation/sessions'); bodies.push(JSON.parse(options.body)); return response(base); });
  await api.start(event); await api.start(event);
  assert.deepEqual(bodies, [{ command_id: event }, { command_id: event }]);
});
test('GET restaura vínculo sem PIN, mutação ou consulta central', async () => {
  const calls = [];
  const api = new DevApi(async (path, options) => { calls.push(path); assert.equal(options.method, 'GET'); assert.equal(options.body, undefined); return response(path.endsWith('active') ? { snapshot: bound } : bound); });
  assert.deepEqual(await api.active(), bound); assert.deepEqual(await api.session(event), bound);
  assert.equal(calls.length, 2); assert.ok(calls.every(p => p.startsWith('/local/simulation/sessions/')));
});
test('Identificação usa os IDs selecionados e PIN somente no JSON local', async () => {
  await new DevApi(async (path, options) => {
    assert.equal(path, `/local/dev/sessions/${event}/identity`);
    assert.equal(options.headers['X-Totem-Request'], '1'); assert.equal(options.headers['X-Api-Key'], undefined);
    assert.equal(options.redirect, 'error');
    assert.deepEqual(JSON.parse(options.body), { class_id: classId, student_id: student, pin: '0012' });
    return response(bound);
  }).identify(event, classId, student, '0012');
});
test('Formato de PIN inválido é recusado antes de qualquer HTTP', async () => {
  let calls = 0;
  const api = new DevApi(async () => { calls++; return response(bound); });
  for (const pin of ['123', '12345', 'abcd', '１２３４', null, 1234]) await assert.rejects(() => api.identify(event, classId, student, pin), e => e.status === 422 && !e.message.includes(String(pin)));
  assert.equal(calls, 0);
});
test('Respostas inconsistentes não confirmam autenticação nem recibo', async () => {
  for (const bad of [{ ...bound, commands: [null] }, { ...bound, session: { ...bound.session, mode: 'class_only' } }, { ...bound, identity: null }, { ...bound, source: 'PHYSICAL' }, { ...bound, identity: { ...bound.identity, student_id: event } }, { ...bound, session: { ...bound.session, receipt: {} } }, { ...bound, identity: { ...bound.identity, validated_at: 'bad' } }, { ...bound, allowed_actions: ['invented'] }]) {
    await assert.rejects(() => new DevApi(async () => response(bad)).identify(event, classId, student, '0012'), e => e.code === 'INVALID_RESPONSE');
  }
});
test('401/422/409/503 e timeout preservam erro seguro e status', async () => {
  for (const status of [401, 422, 409, 503]) await assert.rejects(() => new DevApi(async () => response({ error: { code: 'CONTROLLED', message: 'private-input' } }, status)).identify(event, classId, student, '0012'), e => e.status === status && !e.message.includes('private-input'));
  await assert.rejects(() => new DevApi(async () => { throw Object.assign(new Error('private-input'), { name: 'AbortError' }); }).active(), e => e.code === 'LOCAL_TIMEOUT' && !e.message.includes('private-input'));
});
test('Conclusão simulada sem recibo é distinta de confirmação econômica', async () => {
  const done = { ...bound, session: { ...bound.session, state: 'COMPLETED' }, allowed_actions: [] };
  assert.equal((await new DevApi(async () => response(done)).session(event)).session.receipt, null);
  await assert.rejects(() => new DevApi(async () => { throw new Error('must not call'); }).action(event, 'retry-registration'), e => e.code === 'DEV_ACTION_NOT_SUPPORTED');
});

test('Segurança DEV envia somente booleano à rota existente e lê o snapshot durável', async () => {
  for (const hasRisk of [false, true]) {
    const expected = { ...bound, session: { ...bound.session, state: hasRisk ? 'CANCELLED' : 'PHYSICAL_BLOCKED', failure_code: hasRisk ? 'SAFETY_RISK' : 'SIMULATION_SAFETY_CLEARED' }, allowed_actions: hasRisk ? [] : ['open', 'cancel'] };
    const api = new DevApi(async (path, options) => {
      assert.equal(path, `/local/simulation/sessions/${event}/safety`);
      assert.equal(options.method, 'POST'); assert.equal(options.headers['X-Totem-Request'], '1');
      assert.equal(options.redirect, 'error'); assert.equal(options.headers.Authorization, undefined);
      assert.deepEqual(JSON.parse(options.body), { has_risk: hasRisk });
      return response(expected);
    });
    assert.deepEqual(await api.safety(event, hasRisk), expected);
  }
});

test('Segurança recusa formato inválido antes do HTTP e resposta inconsistente não confirma decisão', async () => {
  let calls = 0;
  const api = new DevApi(async () => { calls++; return response(bound); });
  for (const hasRisk of ['false', 'true', 0, 1, null, undefined]) await assert.rejects(() => api.safety(event, hasRisk), e => e.status === 422);
  await assert.rejects(() => api.safety('invalid', false), e => e.status === 422);
  assert.equal(calls, 0);
  const safe = { ...bound, session: { ...bound.session, state: 'PHYSICAL_BLOCKED' }, allowed_actions: ['open', 'cancel'] };
  for (const data of [bound, { ...safe, session: { ...safe.session, event_id: machine } }, { ...safe, source: 'PHYSICAL' }, { ...safe, identity: null }]) {
    await assert.rejects(() => new DevApi(async () => response(data)).safety(event, false), e => e.code === 'INVALID_RESPONSE');
  }
  await assert.rejects(() => new DevApi(async () => response(safe)).safety(event, true), e => e.code === 'INVALID_RESPONSE');
});

test('Segurança preserva HTTP 409/422/503 e erro de transporte, sem sucesso local', async () => {
  for (const status of [409, 422, 503]) await assert.rejects(() => new DevApi(async () => response({ error: { code: 'CONTROLLED' } }, status)).safety(event, false), e => e.status === status);
  await assert.rejects(() => new DevApi(async () => { throw Object.assign(new Error('private-input'), { name: 'AbortError' }); }).safety(event, true), e => e.code === 'LOCAL_TIMEOUT' && !e.message.includes('private-input'));
});
