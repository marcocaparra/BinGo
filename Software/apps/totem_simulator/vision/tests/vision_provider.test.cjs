const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  VisionResult,
  VisionOrigin,
  CascadingVisionProvider,
  MockVisionProvider,
  RemoteVisionProvider,
  createVisionProvider,
  normalizeResult,
} = require('../vision_provider.js');

const frame = { blob: new Blob(['frame'], { type: 'image/jpeg' }), width: 640, height: 480 };

function provider() {
  return new MockVisionProvider({ primaryDelayMs: 0, secondaryDelayMs: 0 });
}

test('primary mock recognizes the captured item with a normalized contract', async () => {
  const result = await provider().analyze({ frame, scenario: 'success' });
  assert.deepEqual(result, {
    status: VisionResult.RECOGNIZED,
    itemId: 'cable',
    candidateIds: ['cable', 'small', 'phone'],
    confidence: 0.93,
    origin: 'VISION_PRIMARY',
  });
  assert.equal(Object.isFrozen(result), true);
});

test('uncertain primary result requests the controlled secondary analysis', async () => {
  const result = await provider().analyze({ frame, scenario: 'uncertain' });
  assert.equal(result.status, VisionResult.NEEDS_SECONDARY);
  assert.equal(result.origin, 'VISION_PRIMARY');
  assert.deepEqual(result.candidateIds, ['cable', 'small', 'phone']);
});

test('secondary analysis returns its own origin and correction candidates', async () => {
  const result = await provider().analyze({ frame, stage: 'secondary', scenario: 'uncertain' });
  assert.equal(result.status, VisionResult.RECOGNIZED);
  assert.equal(result.origin, 'VISION_SECONDARY');
  assert.deepEqual(result.candidateIds, ['cable', 'battery', 'small']);
});

test('rejected scenario never invents an item id', async () => {
  const result = await provider().analyze({ frame, scenario: 'rejected' });
  assert.equal(result.status, VisionResult.REJECTED);
  assert.equal(result.itemId, null);
});

test('simulation works without allocating a captured image', async () => {
  const result = await provider().analyze({ frame: { simulated: true } });
  assert.equal(result.status, VisionResult.RECOGNIZED);
});

test('real mode refuses to classify without a captured frame', async () => {
  await assert.rejects(provider().analyze({ frame: { simulated: false } }), { name: 'MissingVisionFrameError' });
});

test('an in-flight analysis can be cancelled when the screen changes', async () => {
  const slowProvider = new MockVisionProvider({ primaryDelayMs: 100 });
  const operation = new AbortController();
  const pending = slowProvider.analyze({ frame, signal: operation.signal });
  operation.abort();
  await assert.rejects(pending, { name: 'AbortError' });
});

test('malformed adapter responses are rejected at the provider boundary', () => {
  assert.throws(() => normalizeResult({ status: 'maybe' }, 'primary'), { name: 'InvalidVisionResponseError' });
  assert.throws(() => normalizeResult({ status: VisionResult.RECOGNIZED }, 'primary'), { name: 'InvalidVisionResponseError' });
});

test('a confident Rekognition result finishes without invoking Gemini', async () => {
  let geminiCalls = 0;
  const cascade = new CascadingVisionProvider({
    rekognitionProvider: {
      analyze: async () => ({ status: VisionResult.RECOGNIZED, itemId: 'cable', confidence: 0.91 }),
    },
    geminiProvider: {
      analyze: async () => {
        geminiCalls += 1;
        return { status: VisionResult.RECOGNIZED, itemId: 'cable', confidence: 0.82 };
      },
    },
  });

  const result = await cascade.analyze({ frame });
  assert.equal(result.status, VisionResult.RECOGNIZED);
  assert.equal(result.origin, VisionOrigin.REKOGNITION);
  assert.equal(geminiCalls, 0);
});

test('a low-confidence Rekognition result requests the Gemini fallback', async () => {
  const cascade = new CascadingVisionProvider({
    rekognitionProvider: {
      analyze: async () => ({
        status: VisionResult.RECOGNIZED,
        itemId: 'phone',
        candidateIds: ['small'],
        confidence: 0.62,
      }),
    },
    geminiProvider: {
      analyze: async () => ({ status: VisionResult.RECOGNIZED, itemId: 'phone', confidence: 0.86 }),
    },
    fallbackThreshold: 0.75,
  });

  const result = await cascade.analyze({ frame });
  assert.equal(result.status, VisionResult.NEEDS_SECONDARY);
  assert.equal(result.itemId, null);
  assert.equal(result.origin, VisionOrigin.REKOGNITION);
  assert.deepEqual(result.candidateIds, ['phone', 'small']);
});

test('secondary analysis is delegated to Gemini and identified as fallback', async () => {
  let rekognitionCalls = 0;
  const cascade = createVisionProvider({
    rekognitionProvider: {
      analyze: async () => {
        rekognitionCalls += 1;
        return { status: VisionResult.NEEDS_SECONDARY, confidence: 0.45 };
      },
    },
    geminiProvider: {
      analyze: async () => ({
        status: VisionResult.RECOGNIZED,
        itemId: 'battery',
        candidateIds: ['battery', 'small'],
        confidence: 0.84,
      }),
    },
  });

  const result = await cascade.analyze({ frame, stage: 'secondary' });
  assert.equal(result.status, VisionResult.RECOGNIZED);
  assert.equal(result.origin, VisionOrigin.GEMINI);
  assert.equal(result.itemId, 'battery');
  assert.equal(rekognitionCalls, 0);
});

test('real cascade cannot be enabled with only one configured adapter', () => {
  assert.throws(
    () => createVisionProvider({ rekognitionProvider: { analyze: async () => ({}) } }),
    { name: 'VisionIntegrationUnavailableError' },
  );
});

test('remote provider sends the captured frame to the local edge contract', async () => {
  let request;
  const remote = new RemoteVisionProvider({
    endpoint: 'http://127.0.0.1:8765/vision/analyze',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        status: 200,
        json: async () => ({ status: VisionResult.RECOGNIZED, itemId: 'cable', candidateIds: ['cable'], confidence: 0.94, origin: VisionOrigin.REKOGNITION }),
      };
    },
  });
  const result = await remote.analyze({ frame });
  assert.equal(request.url, 'http://127.0.0.1:8765/vision/analyze?stage=primary');
  assert.equal(request.options.body, frame.blob);
  assert.equal(result.itemId, 'cable');
});

test('remote provider falls back to manual review when secondary service is unavailable', async () => {
  let calls = 0;
  let secondaryUrl;
  const remote = new RemoteVisionProvider({
    endpoint: 'http://127.0.0.1:8765/vision/analyze',
    fetchImpl: async (url) => {
      calls += 1;
      if (calls === 1) return { ok: true, status: 200, json: async () => ({ status: VisionResult.NEEDS_SECONDARY, candidateIds: ['phone', 'small'], confidence: 0.6 }) };
      secondaryUrl = url;
      return { ok: false, status: 501 };
    },
  });
  const primary = await remote.analyze({ frame });
  assert.equal(primary.status, VisionResult.NEEDS_SECONDARY);
  const secondary = await remote.analyze({ frame, stage: 'secondary' });
  assert.equal(secondary.status, VisionResult.RECOGNIZED);
  assert.equal(secondary.itemId, 'unknown');
  assert.equal(secondary.origin, VisionOrigin.MANUAL);
  assert.deepEqual(secondary.candidateIds, ['phone', 'small']);
  assert.equal(secondaryUrl, 'http://127.0.0.1:8765/vision/analyze?stage=secondary&candidates=phone%2Csmall');
});

test('remote provider exposes a real Gemini fallback result', async () => {
  let calls = 0;
  const remote = new RemoteVisionProvider({
    endpoint: 'http://127.0.0.1:8765/vision/analyze',
    fetchImpl: async () => {
      calls += 1;
      if (calls === 1) return { ok: true, status: 200, json: async () => ({ status: VisionResult.NEEDS_SECONDARY, candidateIds: ['battery'], confidence: 0.9, origin: VisionOrigin.REKOGNITION }) };
      return { ok: true, status: 200, json: async () => ({ status: VisionResult.RECOGNIZED, itemId: 'battery', candidateIds: ['battery'], confidence: 0.97, origin: VisionOrigin.GEMINI }) };
    },
  });
  const primary = await remote.analyze({ frame });
  assert.equal(primary.status, VisionResult.NEEDS_SECONDARY);
  const secondary = await remote.analyze({ frame, stage: 'secondary' });
  assert.equal(secondary.itemId, 'battery');
  assert.equal(secondary.origin, VisionOrigin.GEMINI);
});

test('remote provider preserves cascade failure details for the operational UI', async () => {
  const remote = new RemoteVisionProvider({
    endpoint: 'http://127.0.0.1:8765/vision/analyze',
    fetchImpl: async () => ({
      ok: false,
      status: 502,
      json: async () => ({ error: 'vision_provider_failed', provider: 'VISION_CASCADE' }),
    }),
  });
  await assert.rejects(
    remote.analyze({ frame }),
    error => error.name === 'VisionServiceError' && error.provider === 'VISION_CASCADE',
  );
});
