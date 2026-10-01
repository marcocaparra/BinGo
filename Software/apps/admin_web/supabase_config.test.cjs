const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, readFileSync, writeFileSync, rmSync, existsSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
const { generateConfig, validateConfig } = require('./scripts/generate-supabase-config.cjs');

const config = {
  SUPABASE_URL: 'https://project.example.test',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_public_test_fixture',
};
function jwt(role, header = { alg: 'HS256', typ: 'JWT' }) {
  return [header, { role }]
    .map((part) => Buffer.from(JSON.stringify(part)).toString('base64url'))
    .concat(Buffer.alloc(32, 1).toString('base64url'))
    .join('.');
}
function temporary(t) {
  const directory = mkdtempSync(join(tmpdir(), 'bingo-admin-config-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return join(directory, 'supabase-config.json');
}

test('publishable env generates only public contract fields', (t) => {
  const target = temporary(t);
  assert.equal(
    generateConfig({ env: { ...config, VERCEL: '1', UNRELATED_SECRET: 'excluded' }, target }),
    'generated',
  );
  assert.deepEqual(JSON.parse(readFileSync(target, 'utf8')), config);
});

test('JWT anon accepted and written', (t) => {
  const target = temporary(t);
  const expected = { ...config, SUPABASE_PUBLISHABLE_KEY: jwt('anon') };
  generateConfig({ env: expected, target });
  assert.deepEqual(JSON.parse(readFileSync(target, 'utf8')), expected);
});

test('Vercel missing env fails even with a valid existing local file', (t) => {
  const target = temporary(t);
  writeFileSync(target, JSON.stringify(config));
  assert.throws(() => generateConfig({ env: { VERCEL: '1' }, target }), /Build Vercel exige/);
  assert.deepEqual(JSON.parse(readFileSync(target, 'utf8')), config);
});

test('partial env fails rather than falling back to local config', (t) => {
  const target = temporary(t);
  writeFileSync(target, JSON.stringify(config));
  for (const env of [
    { SUPABASE_URL: config.SUPABASE_URL },
    { SUPABASE_PUBLISHABLE_KEY: config.SUPABASE_PUBLISHABLE_KEY },
  ])
    assert.throws(() => generateConfig({ env, target }), /informadas juntas/);
});

test('invalid URL and empty values rejected', () => {
  for (const url of ['not-a-url', 'ftp://project.test', 'https://user:secret@project.test', ''])
    assert.throws(() => validateConfig({ ...config, SUPABASE_URL: url }));
  for (const key of ['', '   '])
    assert.throws(() => validateConfig({ ...config, SUPABASE_PUBLISHABLE_KEY: key }));
  assert.equal(
    validateConfig({ ...config, SUPABASE_URL: 'http://127.0.0.1:54321' }).SUPABASE_URL,
    'http://127.0.0.1:54321',
  );
});

test('service_role JWT, secret key and malformed formats rejected without writing', (t) => {
  const target = temporary(t);
  for (const key of [
    jwt('service_role'),
    jwt('authenticated'),
    'sb_secret_private_fixture',
    'sb_publishable_',
    'sb_publishable_invalid!',
    'invalid',
    'aaa.bbb.ccc',
    jwt('anon', { alg: 'none' }),
    jwt('anon', { alg: '' }),
    jwt('anon', {}),
    jwt('anon').split('.').slice(0, 2).join('.'),
  ]) {
    assert.throws(
      () => generateConfig({ env: { ...config, SUPABASE_PUBLISHABLE_KEY: key }, target }),
      /chave pública/,
    );
    assert.equal(existsSync(target), false);
  }
});

test('valid local file, including BOM, is preserved byte for byte', (t) => {
  const target = temporary(t);
  const original = `\uFEFF${JSON.stringify({ ...config, SUPABASE_PUBLISHABLE_KEY: jwt('anon') }, null, 4)}\r\n`;
  writeFileSync(target, original);
  assert.equal(generateConfig({ env: {}, target }), 'preserved');
  assert.equal(readFileSync(target, 'utf8'), original);
});

test('missing or invalid local config fails closed', (t) => {
  const target = temporary(t);
  assert.throws(() => generateConfig({ env: {}, target }), /local válido/);
  writeFileSync(target, '{invalid');
  assert.throws(() => generateConfig({ env: {}, target }), /local válido/);
  writeFileSync(
    target,
    JSON.stringify({ ...config, SUPABASE_PUBLISHABLE_KEY: jwt('service_role') }),
  );
  assert.throws(() => generateConfig({ env: {}, target }), /chave pública/);
});

test('invalid env never overwrites existing config', (t) => {
  const target = temporary(t);
  const original = JSON.stringify(config);
  writeFileSync(target, original);
  assert.throws(() =>
    generateConfig({ env: { ...config, SUPABASE_PUBLISHABLE_KEY: jwt('service_role') }, target }),
  );
  assert.equal(readFileSync(target, 'utf8'), original);
});

test('CLI failure has nonzero exit and never logs complete key', () => {
  const key = jwt('service_role');
  const result = spawnSync(
    process.execPath,
    [join(__dirname, 'scripts/generate-supabase-config.cjs')],
    {
      env: { ...process.env, VERCEL: '1', ...config, SUPABASE_PUBLISHABLE_KEY: key },
      encoding: 'utf8',
    },
  );
  assert.equal(result.status, 1);
  assert.ok(!`${result.stdout}${result.stderr}`.includes(key));
});
