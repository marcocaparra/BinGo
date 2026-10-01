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
    products: [
      {
        reward_id: '50000000-0000-4000-8000-000000000001',
        name: 'Produto RPC',
        description: 'Descrição RPC',
        category: null,
        cost_points: 1200,
        is_active: true,
        stock_qty: 8,
      },
      {
        reward_id: '50000000-0000-4000-8000-000000000002',
        name: 'Ilimitado RPC',
        description: null,
        category: null,
        cost_points: 900,
        is_active: false,
        stock_qty: null,
      },
    ],
    redemptions: [
      {
        redemption_id: '60000000-0000-4000-8000-000000000001',
        code: 'BGO-123456789ABC',
        status: 'PENDING',
        student_id: '30000000-0000-4000-8000-000000000001',
        student_name: 'Aluno RPC',
        registration: '0001',
        class_id: '20000000-0000-4000-8000-000000000001',
        class_name: 'Turma RPC',
        reward_id: '50000000-0000-4000-8000-000000000001',
        reward_name_snapshot: 'Snapshot RPC',
        cost_points_snapshot: 1000,
        created_at: '2026-09-30T12:00:00Z',
        delivered_at: null,
        canceled_at: null,
        delivered_by_admin_id: null,
        delivered_by_admin_name: null,
      },
    ],
    classRequests: [
      {
        request_id: '70000000-0000-4000-8000-000000000001',
        student_id: '30000000-0000-4000-8000-000000000001',
        student_name: 'Aluno RPC',
        registration: '0001',
        source_class_id: '20000000-0000-4000-8000-000000000001',
        source_class_name: 'Turma RPC',
        destination_class_id: '20000000-0000-4000-8000-000000000002',
        destination_class_name: 'Turma destino RPC',
        current_class_id: '20000000-0000-4000-8000-000000000001',
        current_class_name: 'Turma RPC',
        status: 'PENDING',
        is_stale: false,
        requested_by_admin_id: adminId,
        requested_by_admin_name: 'Solicitante RPC',
        created_at: '2026-09-30T12:00:00Z',
        resolved_by_admin_id: null,
        resolved_by_admin_name: null,
        resolved_at: null,
      },
    ],
    students: [
      {
        student_id: '30000000-0000-4000-8000-000000000001',
        name: 'Aluno RPC',
        email: 'aluno@example.test',
        registration: '0001',
        class_id: '20000000-0000-4000-8000-000000000001',
        class_name: 'Turma RPC',
        status: 'ACTIVE',
        points_student_balance: 800,
        class_points_balance: 1900,
      },
    ],
    classes: [
      {
        class_id: '20000000-0000-4000-8000-000000000001',
        segment: 'Segmento livre',
        grade: 'Série livre',
        name: 'Turma RPC',
        points_class_balance: 1900,
        student_count: 1,
      },
      {
        class_id: '20000000-0000-4000-8000-000000000002',
        segment: 'Outro segmento',
        grade: 'Outra série',
        name: 'Turma destino RPC',
        points_class_balance: 3000,
        student_count: 0,
      },
    ],
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
    const rpc = path.replace('/rest/v1/rpc/', '');
    const body = request.postDataJSON();
    assert.ok(
      [
        'get_my_admin_context_v1',
        'get_admin_binbazar_products_v1',
        'update_admin_binbazar_product_v1',
        'get_admin_redemptions_v1',
        'deliver_admin_redemption_v1',
        'cancel_admin_redemption_v1',
        'get_class_change_requests_v1',
        'create_class_change_request_v1',
        'approve_class_change_request_v1',
        'reject_class_change_request_v1',
        'cancel_class_change_request_v1',
        'get_admin_students_v1',
        'get_admin_classes_v1',
        'create_admin_student_v1',
        'update_admin_student_v1',
        'create_admin_class_v1',
        'update_admin_class_v1',
      ].includes(rpc),
      `RPC fora da fatia: ${rpc}`,
    );
    if (rpc.includes('binbazar') || rpc.includes('admin_redemption')) {
      if (fixture.binbazarWait) await fixture.binbazarWait;
      if (fixture.binbazarError)
        return route.fulfill({ status: 503, json: { message: 'Unavailable' } });
      if (rpc.startsWith('get_')) {
        assert.deepEqual(body, {});
        return route.fulfill({
          json: rpc.includes('products') ? fixture.products : fixture.redemptions,
        });
      }
      if (fixture.binbazarMutationWait) await fixture.binbazarMutationWait;
      if (fixture.binbazarMutationError)
        return route.fulfill({
          status: 409,
          json: { code: fixture.binbazarMutationError, message: 'Conflict' },
        });
      if (rpc.startsWith('update_')) {
        assert.deepEqual(
          Object.keys(body).sort(),
          ['p_reward_id', 'p_name', 'p_description', 'p_stock_qty', 'p_is_active'].sort(),
        );
        const p = fixture.products.find((p) => p.reward_id === body.p_reward_id);
        Object.assign(p, {
          name: body.p_name,
          description: body.p_description,
          stock_qty: body.p_stock_qty,
          is_active: body.p_is_active,
        });
        return route.fulfill({ json: p.reward_id });
      }
      assert.deepEqual(Object.keys(body), ['p_redemption_id']);
      const r = fixture.redemptions.find((r) => r.redemption_id === body.p_redemption_id);
      r.status = rpc.startsWith('deliver') ? 'DELIVERED' : 'CANCELED';
      if (r.status === 'DELIVERED') {
        r.delivered_at = new Date().toISOString();
        r.delivered_by_admin_id = adminId;
        r.delivered_by_admin_name = 'Admin RPC';
      } else r.canceled_at = new Date().toISOString();
      return route.fulfill({ json: r.redemption_id });
    }
    if (rpc.includes('class_change_request')) {
      if (fixture.requestWait) await fixture.requestWait;
      if (fixture.requestError)
        return route.fulfill({ status: 503, json: { message: 'Unavailable' } });
      const rows = () =>
        fixture.classRequests
          .filter((r) => fixture.role === 'ADMIN_B' || r.requested_by_admin_id === adminId)
          .map((r) => {
            const student = fixture.students.find((s) => s.student_id === r.student_id);
            return {
              ...r,
              current_class_id: student?.class_id,
              current_class_name: fixture.classes.find((c) => c.class_id === student?.class_id)
                ?.name,
              is_stale: r.status === 'PENDING' && student?.class_id !== r.source_class_id,
            };
          });
      if (rpc.startsWith('get_')) {
        assert.deepEqual(body, {});
        return route.fulfill({ json: rows() });
      }
      if (fixture.requestMutationWait) await fixture.requestMutationWait;
      const denied = () =>
        route.fulfill({
          status: 403,
          json: { code: '42501', message: 'CLASS_CHANGE_ACCESS_DENIED' },
        });
      if (rpc.startsWith('create')) {
        assert.deepEqual(
          Object.keys(body).sort(),
          ['p_request_id', 'p_student_id', 'p_destination_class_id'].sort(),
        );
        if (fixture.role !== 'ADMIN_C') return denied();
        let row = fixture.classRequests.find((r) => r.request_id === body.p_request_id);
        if (
          row &&
          (row.student_id !== body.p_student_id ||
            row.destination_class_id !== body.p_destination_class_id)
        )
          return route.fulfill({
            status: 409,
            json: { code: '23505', message: 'CLASS_CHANGE_REQUEST_ID_CONFLICT' },
          });
        if (!row) {
          const student = fixture.students.find((s) => s.student_id === body.p_student_id);
          const src = fixture.classes.find((c) => c.class_id === student?.class_id),
            dst = fixture.classes.find((c) => c.class_id === body.p_destination_class_id);
          if (!student || !dst) return denied();
          if (src.class_id === dst.class_id)
            return route.fulfill({
              status: 400,
              json: { code: '22023', message: 'CLASS_CHANGE_SAME_CLASS' },
            });
          row = {
            request_id: body.p_request_id,
            student_id: student.student_id,
            student_name: student.name,
            registration: student.registration,
            source_class_id: src.class_id,
            source_class_name: src.name,
            destination_class_id: dst.class_id,
            destination_class_name: dst.name,
            status: 'PENDING',
            requested_by_admin_id: adminId,
            requested_by_admin_name: 'Solicitante RPC',
            created_at: new Date().toISOString(),
            resolved_by_admin_id: null,
            resolved_by_admin_name: null,
            resolved_at: null,
          };
          fixture.classRequests.unshift(row);
        }
        if (fixture.loseCreateResponse) {
          fixture.loseCreateResponse = false;
          return route.abort('failed');
        }
        return route.fulfill({ json: row.request_id });
      }
      assert.deepEqual(Object.keys(body), ['p_request_id']);
      const row = fixture.classRequests.find((r) => r.request_id === body.p_request_id);
      const cancel = rpc.startsWith('cancel');
      if (
        !row ||
        (cancel
          ? fixture.role !== 'ADMIN_C' || row.requested_by_admin_id !== adminId
          : fixture.role !== 'ADMIN_B')
      )
        return denied();
      const target = cancel ? 'CANCELED' : rpc.startsWith('approve') ? 'APPROVED' : 'REJECTED';
      if (row.status === target) return route.fulfill({ json: row.request_id });
      if (row.status !== 'PENDING')
        return route.fulfill({
          status: 400,
          json: { code: 'P0001', message: 'CLASS_CHANGE_DECISION_CONFLICT' },
        });
      const student = fixture.students.find((s) => s.student_id === row.student_id);
      if (target === 'APPROVED') {
        if (student.class_id !== row.source_class_id)
          return route.fulfill({
            status: 400,
            json: { code: 'P0001', message: 'CLASS_CHANGE_REQUEST_STALE' },
          });
        student.class_id = row.destination_class_id;
      }
      Object.assign(row, {
        status: target,
        resolved_by_admin_id: adminId,
        resolved_by_admin_name: 'Decisor RPC',
        resolved_at: new Date().toISOString(),
      });
      return route.fulfill({ json: row.request_id });
    }
    if (rpc !== 'get_my_admin_context_v1') {
      if (fixture.schoolWait) await fixture.schoolWait;
      if (fixture.schoolError)
        return route.fulfill({ status: 503, json: { message: 'Unavailable' } });
      if (rpc.startsWith('get_')) {
        assert.deepEqual(body, {});
        const students = fixture.students.map((s) => ({
          ...s,
          class_name: fixture.classes.find((c) => c.class_id === s.class_id)?.name,
          class_points_balance: fixture.classes.find((c) => c.class_id === s.class_id)
            ?.points_class_balance,
        }));
        return route.fulfill({
          json: rpc === 'get_admin_students_v1' ? students : fixture.classes,
        });
      }
      for (const forbidden of [
        'p_school_id',
        'p_actor_id',
        'p_role',
        'p_points_student_balance',
        'p_auth_user_id',
        'p_pin_hash',
        'p_points_class_balance',
        'p_is_activated',
      ])
        assert.equal(body[forbidden], undefined);
      if (fixture.role !== 'ADMIN_B')
        return route.fulfill({
          status: 403,
          json: { code: '42501', message: 'ADMIN_SCHOOL_ACCESS_DENIED' },
        });
      if (rpc.includes('_student_')) {
        if (
          fixture.students.some(
            (s) => s.registration === body.p_registration && s.student_id !== body.p_student_id,
          )
        )
          return route.fulfill({
            status: 409,
            json: { code: '23505', message: 'ADMIN_REGISTRATION_CONFLICT' },
          });
        const row = {
          student_id: body.p_student_id || require('node:crypto').randomUUID(),
          name: body.p_name,
          email: body.p_email,
          registration: body.p_registration,
          class_id: body.p_class_id,
          status: body.p_status,
          points_student_balance: 0,
          class_points_balance: 0,
          class_name: '',
        };
        if (rpc.startsWith('create')) fixture.students.push(row);
        else
          fixture.students = fixture.students.map((s) =>
            s.student_id === row.student_id
              ? { ...s, ...row, points_student_balance: s.points_student_balance }
              : s,
          );
        return route.fulfill({ json: row.student_id });
      }
      const row = {
        class_id: body.p_class_id || require('node:crypto').randomUUID(),
        name: body.p_name,
        segment: body.p_segment,
        grade: body.p_grade,
        points_class_balance: 0,
        student_count: 0,
      };
      if (rpc.startsWith('create')) fixture.classes.push(row);
      else
        fixture.classes = fixture.classes.map((c) =>
          c.class_id === row.class_id
            ? { ...c, ...row, points_class_balance: c.points_class_balance }
            : c,
        );
      return route.fulfill({ json: row.class_id });
    }
    assert.deepEqual(body, {});
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
