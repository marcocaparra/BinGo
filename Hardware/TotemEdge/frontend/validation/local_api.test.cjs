const { test } = require('node:test');
const assert = require('node:assert/strict');
const { LocalApi } = require('../local_api.js');
const response = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const id = '00000000-0000-4000-8000-000000000001';
const base = { event_id: id, class_id: id, mode: 'class_only', state: 'REGISTRATION_PENDING', receipt: null };

test('Consulta somente status local, sem credencial ou destino remoto', async () => {
  const api = new LocalApi(async (path, options) => {
    assert.equal(path, '/local/status'); assert.equal(options.cache, 'no-store');
    assert.equal(options.headers['X-Api-Key'], undefined);
    return response({ status: 'OFFLINE', can_start_deposit: false, message: 'Indisponível' });
  });
  assert.equal((await api.status()).can_start_deposit, false);
});
for (const body of [{ status: 'ONLINE', can_start_deposit: false, message: null }, { status: 'OFFLINE', can_start_deposit: 'false', message: 'x' }, {}]) {
  test('Resposta de disponibilidade inválida não libera fluxo ' + JSON.stringify(body), async () => {
    await assert.rejects(() => new LocalApi(async () => response(body)).status());
  });
}
test('Falha de rede e resposta não JSON são seguras', async () => {
  await assert.rejects(() => new LocalApi(async () => { throw new Error('private-input'); }).status(), error => error.code === 'LOCAL_UNAVAILABLE' && !error.message.includes('private-input'));
  await assert.rejects(() => new LocalApi(async () => new Response('bad')).status());
});
test('Estado confirmado exige recibo central vinculado ao evento', async () => {
  await assert.rejects(() => new LocalApi(async () => response({ ...base, state: 'REGISTERED' })).session(id));
  const receipt = { id, event_id: id, points_awarded_student: 0, points_awarded_class: 1900, bonus_bincoins_awarded: 0 };
  assert.equal((await new LocalApi(async () => response({ ...base, state: 'REGISTERED', receipt })).session(id)).receipt.points_awarded_class, 1900);
  await assert.rejects(() => new LocalApi(async () => response({ ...base, receipt })).session(id));
});
test('Retry não envia novo evento ou payload; PIN só em JSON local', async () => {
  const calls = [];
  const api = new LocalApi(async (path, options) => { calls.push({ path, options }); return response(base); });
  await api.action(id, 'retry-registration');
  assert.equal(calls[0].options.body, '{}');
  await api.action(id, 'pin', { student_id: id, pin: '0012' });
  assert.ok(!calls[1].path.includes('0012'));
  assert.equal(JSON.parse(calls[1].options.body).pin, '0012');
  assert.equal(calls[1].options.headers['X-Totem-Request'], '1');
});
