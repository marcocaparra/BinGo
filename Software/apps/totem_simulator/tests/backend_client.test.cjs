const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  createClient,
  loopbackUrl,
  PENDING_KEY,
} = require("../backend_client.js");
function storage() {
  const values = new Map();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  };
}
const payload = {
  event_id: "a0000000-0000-4000-8000-000000000001",
  class_id: "20000000-0000-4000-8000-000000000001",
  student_id: "30000000-0000-4000-8000-000000000001",
  is_valid: true,
  detected_type: "pilha",
  waste_category_code: "BATTERY",
  category_source: "AI_CONFIRMED",
};
const snapshot = {
  id: "b0000000-0000-4000-8000-000000000001",
  event_id: payload.event_id,
  points_awarded_student: 123,
  points_awarded_class: 456,
  bonus_bincoins_awarded: 23,
};
test("browser only connects to loopback, never carries a machine secret", async () => {
  for (const url of [
    "https://example.com",
    "http://127.0.0.1.evil.test",
    "http://user:secret@localhost:8765",
    "file:///tmp",
  ])
    assert.throws(() => loopbackUrl(url));
  const client = createClient({
    storage: storage(),
    fetchImpl: async (url, options) => {
      assert.equal(url, "http://127.0.0.1:8765/bingo/context");
      assert.deepEqual(options.headers, { "Content-Type": "application/json" });
      return Response.json({ classes: [] });
    },
  });
  assert.deepEqual(await client.request("context"), { classes: [] });
});
test("readiness permits only 200 AVAILABLE and true", async () => {
  for (const [status, body] of [
    [200, { status: "UNAVAILABLE", can_start_deposit: true }],
    [200, { status: "AVAILABLE", can_start_deposit: false }],
    [200, {}],
    [201, { status: "AVAILABLE", can_start_deposit: true }],
    [401, {}],
    [500, {}],
    [503, {}],
  ]) {
    await assert.rejects(
      createClient({
        storage: storage(),
        fetchImpl: async () => Response.json(body, { status }),
      }).readiness(),
    );
  }
  await createClient({
    storage: storage(),
    fetchImpl: async () =>
      Response.json({ status: "AVAILABLE", can_start_deposit: true }),
  }).readiness();
});
test("readiness rejects network, timeout and invalid body", async () => {
  for (const fetchImpl of [
    async () => {
      throw new TypeError("offline");
    },
    async () => new Response("invalid"),
    async (_url, { signal }) =>
      new Promise((_resolve, reject) =>
        signal.addEventListener("abort", () => reject(new Error("timeout"))),
      ),
  ]) {
    await assert.rejects(
      createClient({ storage: storage(), fetchImpl, timeoutMs: 5 }).readiness(),
    );
  }
});
test("durable commit precedes request and rejects extra identity/economy/secrets", () => {
  const local = storage();
  const client = createClient({
    storage: local,
    fetchImpl: () => {
      throw new Error("commit must not contact server");
    },
  });
  client.commit(payload);
  assert.deepEqual(JSON.parse(local.getItem(PENDING_KEY)), payload);
  for (const key of ["school_id", "machine_id", "points", "pin", "api_key"])
    assert.throws(() => client.commit({ ...payload, [key]: "forged" }));
  assert.throws(() =>
    client.commit({
      ...payload,
      event_id: "a0000000-0000-4000-8000-000000000002",
    }),
  );
});
for (const status of [200, 201])
  test(`${status} confirmation removes the pending event and trusts backend amounts`, async () => {
    const local = storage();
    const client = createClient({
      storage: local,
      fetchImpl: async (_url, options) => {
        assert.deepEqual(JSON.parse(options.body), payload);
        assert.deepEqual(JSON.parse(local.getItem(PENDING_KEY)), payload);
        return Response.json(snapshot, { status });
      },
    });
    client.commit(payload);
    assert.deepEqual(await client.retryPending(), {
      payload,
      deposit: snapshot,
    });
    assert.equal(client.pending(), null);
  });
for (const status of [401, 404, 409, 422, 500, 502, 503, 504])
  test(`${status} keeps the exact event for recovery`, async () => {
    const local = storage();
    const client = createClient({
      storage: local,
      fetchImpl: async () =>
        Response.json({ error: { message: "failed" } }, { status }),
    });
    client.commit(payload);
    await assert.rejects(
      client.retryPending(),
      (error) => error.status === status,
    );
    assert.deepEqual(client.pending(), payload);
  });
test("unknown result then browser reopens: retry keeps UUID and complete payload", async () => {
  const local = storage();
  const original = createClient({
    storage: local,
    fetchImpl: async () => {
      throw new TypeError("response lost after DB commit");
    },
  });
  original.commit(payload);
  await assert.rejects(original.retryPending());
  const reopened = createClient({
    storage: local,
    fetchImpl: async (_url, options) => {
      assert.deepEqual(JSON.parse(options.body), payload);
      return Response.json(snapshot, { status: 200 });
    },
  });
  assert.deepEqual(reopened.pending(), payload);
  await reopened.retryPending();
  assert.equal(reopened.pending(), null);
});
test("invalid confirmation and storage errors fail closed", async () => {
  const local = storage();
  const client = createClient({
    storage: local,
    fetchImpl: async () => Response.json({ ...snapshot, event_id: "wrong" }),
  });
  client.commit(payload);
  await assert.rejects(client.retryPending());
  assert.deepEqual(client.pending(), payload);
  local.setItem(PENDING_KEY, "{broken");
  assert.throws(() => client.pending());
  const unavailable = createClient({
    storage: {
      ...storage(),
      setItem: () => {
        throw new Error("disk full");
      },
    },
  });
  assert.throws(() => unavailable.commit(payload));
});

test("confirmed backend write stays confirmed if storage cleanup fails; durable replay remains safe", async () => {
  const local = storage();
  local.removeItem = () => {
    throw new Error("storage unavailable");
  };
  const client = createClient({
    storage: local,
    fetchImpl: async () => Response.json(snapshot),
  });
  client.commit(payload);
  assert.deepEqual(await client.retryPending(), {
    payload,
    deposit: snapshot,
    cleanupFailed: true,
  });
  assert.deepEqual(client.pending(), payload);
});
