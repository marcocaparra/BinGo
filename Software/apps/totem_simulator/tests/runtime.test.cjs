const { test } = require("node:test");
const assert = require("node:assert/strict");
const { resolveRuntime } = require("../runtime.js");
const { createClient } = require("../backend_client.js");

test("local defaults stay loopback and vision override cannot escape loopback", () => {
  assert.deepEqual(resolveRuntime(), {
    mode: "local",
    baseUrl: "http://127.0.0.1:8765",
    visionUrl: "http://127.0.0.1:8765/vision/analyze",
  });
  assert.equal(
    resolveRuntime("local", {
      search: "?visionUrl=http://localhost:9999/vision/analyze",
    }).visionUrl,
    "http://localhost:9999/vision/analyze",
  );
  for (const url of [
    "https://remote.test",
    "http://localhost.evil.test",
    "http://secret@localhost",
    "file:///tmp",
  ])
    assert.throws(() =>
      resolveRuntime("local", {
        search: `?visionUrl=${encodeURIComponent(url)}`,
      }),
    );
});

test("cloud ignores URL overrides and backend only accepts same-origin paths", async () => {
  const runtime = resolveRuntime("cloud", {
    search: "?visionUrl=https://evil.test",
  });
  assert.equal(runtime.visionUrl, "/vision/analyze");
  globalThis.BinGoRuntime = runtime;
  try {
    await createClient({
      storage: {},
      fetchImpl: async (url) => {
        assert.equal(url, "/bingo/context");
        return Response.json({ classes: [] });
      },
    }).request("context");
    for (const baseUrl of [
      "https://evil.test",
      "http://127.0.0.1:8765",
      "//evil.test",
    ])
      assert.throws(() => createClient({ baseUrl, storage: {} }));
  } finally {
    delete globalThis.BinGoRuntime;
  }
});
