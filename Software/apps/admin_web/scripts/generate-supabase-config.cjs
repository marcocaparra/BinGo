const { mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const { dirname, join } = require('node:path');

const configPath = join(__dirname, '..', 'public', 'supabase-config.json');

function validateConfig(config) {
  const url = config?.SUPABASE_URL;
  const key = config?.SUPABASE_PUBLISHABLE_KEY;
  if (typeof url !== 'string' || !url.trim() || typeof key !== 'string' || !key.trim())
    throw new Error('Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY não vazias.');
  let parsed;
  try {
    parsed = new URL(url.trim());
  } catch {
    throw new Error('SUPABASE_URL deve ser uma URL http/https válida.');
  }
  if (
    !['http:', 'https:'].includes(parsed.protocol) ||
    !parsed.hostname ||
    parsed.username ||
    parsed.password
  )
    throw new Error('SUPABASE_URL deve ser http/https, sem credenciais embutidas.');

  const publicKey = key.trim();
  let valid = /^sb_publishable_[A-Za-z0-9_-]+$/.test(publicKey);
  if (!valid) {
    try {
      const segments = publicKey.split('.');
      if (segments.length !== 3 || segments.some((part) => !/^[A-Za-z0-9_-]+$/.test(part)))
        throw new Error();
      const decoded = segments.map((part) => {
        const bytes = Buffer.from(part, 'base64url');
        if (bytes.toString('base64url') !== part) throw new Error();
        return bytes;
      });
      const header = JSON.parse(decoded[0].toString('utf8'));
      const payload = JSON.parse(decoded[1].toString('utf8'));
      valid =
        typeof header?.alg === 'string' &&
        /^(?:(?:HS|RS|ES|PS)(?:256|384|512)|EdDSA)$/.test(header.alg) &&
        payload?.role === 'anon';
    } catch {
      valid = false;
    }
  }
  if (!valid)
    throw new Error(
      'Use somente chave pública sb_publishable_* ou JWT anon; service_role/secret são proibidas.',
    );
  return { SUPABASE_URL: url.trim(), SUPABASE_PUBLISHABLE_KEY: publicKey };
}

function generateConfig({ env = process.env, target = configPath } = {}) {
  const hasUrl = env.SUPABASE_URL !== undefined;
  const hasKey = env.SUPABASE_PUBLISHABLE_KEY !== undefined;
  if (hasUrl !== hasKey)
    throw new Error('SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY devem ser informadas juntas.');
  if (hasUrl) {
    const config = validateConfig(env);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
    return 'generated';
  }
  if (env.VERCEL === '1')
    throw new Error('Build Vercel exige SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY.');
  let local;
  try {
    local = JSON.parse(readFileSync(target, 'utf8').replace(/^\uFEFF/, ''));
  } catch {
    throw new Error('Configure as variáveis ou um public/supabase-config.json local válido.');
  }
  validateConfig(local);
  return 'preserved';
}

if (require.main === module) {
  try {
    const result = generateConfig();
    console.log(
      result === 'generated'
        ? 'Configuração pública Supabase gerada.'
        : 'Configuração pública Supabase local preservada.',
    );
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { generateConfig, validateConfig };
