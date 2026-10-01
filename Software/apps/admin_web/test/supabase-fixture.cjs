const assert = require('node:assert/strict');

const schoolId = '10000000-0000-4000-8000-000000000001';
const userId = '90000000-0000-4000-8000-000000000001';
const adminId = '40000000-0000-4000-8000-000000000001';

async function installSupabaseFixture(page, options = {}) {
  const fixture = {
    role: 'ADMIN_C',
    status: 'ACTIVE',
    linked: true,
    invalidCredentials: false,
    networkError: false,
    rpcError: false,
    schoolId,
    calls: [],
    ...options,
  };
  await page.route('**/supabase-config.json', (route) =>
    route.fulfill({
      json: {
        SUPABASE_URL: 'http://127.0.0.1:54321',
        SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test_fixture',
      },
    }),
  );
  const session = () => ({
    access_token: `${Buffer.from('{}').toString('base64url')}.${Buffer.from(JSON.stringify({ sub: userId, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.fixture`,
    refresh_token: 'test-refresh-token',
    token_type: 'bearer',
    expires_in: 3600,
    user: {
      id: userId,
      email: 'admin@example.test',
      role: 'authenticated',
      app_metadata: { provider: 'email' },
      user_metadata: { role: 'ADMIN_A', school_id: 'untrusted' },
      aud: 'authenticated',
      created_at: new Date().toISOString(),
    },
  });
  await page.route('**/auth/v1/**', async (route) => {
    const request = route.request();
    fixture.calls.push({ path: new URL(request.url()).pathname, body: request.postDataJSON() });
    if (fixture.networkError) return route.abort('failed');
    if (request.url().includes('/logout'))
      return fixture.logoutError
        ? route.fulfill({ status: 503, json: { message: 'Unavailable' } })
        : route.fulfill({ status: 204 });
    if (fixture.invalidCredentials)
      return route.fulfill({
        status: 400,
        headers: {
          'x-supabase-api-version': '2024-01-01',
          'access-control-expose-headers': 'x-supabase-api-version',
        },
        json: { code: 'invalid_credentials', msg: 'Invalid login credentials' },
      });
    return route.fulfill({ json: request.url().includes('/user') ? session().user : session() });
  });
  await page.route('**/rest/v1/**', async (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    fixture.calls.push({ path, body: request.postDataJSON() });
    // Auth e identidade sao os unicos acessos remotos permitidos nesta feature.
    assert.equal(path, '/rest/v1/rpc/get_my_admin_context_v1');
    assert.deepEqual(request.postDataJSON(), {}); // SDK sem parametros nao manda identidade.
    if (fixture.rpcWait) await fixture.rpcWait;
    if (fixture.rpcError) return route.fulfill({ status: 503, json: { message: 'Unavailable' } });
    return route.fulfill({
      json: fixture.linked
        ? [
            {
              id: adminId,
              name: 'Administrador Autenticado',
              email: 'admin@example.test',
              role: fixture.role,
              school_id: fixture.role === 'ADMIN_A' ? null : fixture.schoolId,
              status: fixture.status,
            },
          ]
        : [],
    });
  });
  return fixture;
}

async function submitLogin(page) {
  await page.getByLabel('E-mail institucional', { exact: true }).fill('admin@example.test');
  await page.getByLabel('Senha', { exact: true }).fill('test-password');
  await page.getByRole('button', { name: 'Acessar o Admin' }).click();
}

module.exports = { installSupabaseFixture, submitLogin, schoolId };
