const { test } = require('node:test');
const assert = require('node:assert/strict');
const { BinGoCamera } = require('../camera_controller.js');

function fixture(options = {}) {
  const track = { readyState: 'live', stopCount: 0, stop() { this.stopCount++; this.readyState = 'ended'; } };
  const stream = { getTracks: () => [track], getVideoTracks: () => [track] };
  let calls = 0;
  const mediaDevices = { getUserMedia(constraints) { calls++; assert.equal(constraints.audio, false); return Promise.resolve(stream); } };
  const video = { srcObject: null, play: async () => {}, readyState: 2, videoWidth: 640, videoHeight: 480 };
  const canvas = { getContext: () => ({ drawImage() {} }), toBlob: callback => callback(new Blob(['frame'], { type: 'image/jpeg' })) };
  const camera = new BinGoCamera({ mediaDevices, waitForVideo: async () => {}, timeoutMs: 30, ...options });
  return { camera, stream, track, video, canvas, calls: () => calls };
}

test('closed-door gate prevents accessing webcam', async () => {
  const f = fixture();
  await assert.rejects(f.camera.start(f.video, () => false), { name: 'DoorOpenError' });
  assert.equal(f.calls(), 0);
});

test('unsupported contexts fail without pretending to capture', async () => {
  const f = fixture({ mediaDevices: null });
  await assert.rejects(f.camera.start(f.video, () => true), { name: 'NotSupportedError' });
});

test('permission denial propagates and releases operation', async () => {
  const f = fixture({ mediaDevices: { getUserMedia: async () => { throw Object.assign(new Error(), { name: 'NotAllowedError' }); } } });
  await assert.rejects(f.camera.start(f.video, () => true), { name: 'NotAllowedError' });
  assert.equal(f.camera.ready, false);
  assert.equal(f.video.srcObject, null);
});

test('ready webcam captures real frame metadata without audio', async () => {
  const f = fixture();
  await f.camera.start(f.video, () => true);
  assert.equal(f.camera.ready, true);
  const frame = await f.camera.capture(f.canvas, () => true);
  assert.equal(frame.blob.type, 'image/jpeg');
  assert.equal(frame.width, 640);
  assert.equal(frame.height, 480);
  assert.ok(frame.capturedAt);
  f.camera.stop();
  assert.equal(f.track.stopCount, 1);
  assert.equal(f.video.srcObject, null);
});

test('capture checks door again', async () => {
  const f = fixture();
  await f.camera.start(f.video, () => true);
  await assert.rejects(f.camera.capture(f.canvas, () => false), { name: 'DoorOpenError' });
  f.camera.stop();
});

test('door changing during startup releases acquired stream', async () => {
  const f = fixture();
  let checks = 0;
  await assert.rejects(f.camera.start(f.video, () => ++checks === 1), { name: 'DoorOpenError' });
  assert.equal(f.track.stopCount, 1);
});

test('capture cannot happen before camera is ready', async () => {
  const f = fixture();
  await assert.rejects(f.camera.capture(f.canvas, () => true), { name: 'NotReadableError' });
});

test('initial 2x2 placeholder does not enable capture before video resize', async () => {
  const f = fixture({ waitForVideo: undefined, timeoutMs: 250 });
  f.video = Object.assign(new EventTarget(), f.video, { videoWidth: 2, videoHeight: 2 });
  const pending = f.camera.start(f.video, () => true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.camera.ready, false);
  f.video.videoWidth = 640;
  f.video.videoHeight = 480;
  f.video.dispatchEvent(new Event('resize'));
  await pending;
  assert.equal(f.camera.ready, true);
  f.camera.stop();
});

test('blank frames and empty encoding fail', async () => {
  const f = fixture();
  await f.camera.start(f.video, () => true);
  f.video.videoWidth = 0;
  await assert.rejects(f.camera.capture(f.canvas, () => true), { name: 'NotReadableError' });
  f.video.videoWidth = 640;
  f.canvas.toBlob = callback => callback(null);
  await assert.rejects(f.camera.capture(f.canvas, () => true), { name: 'NotReadableError' });
  f.camera.stop();
});

test('late permission result after timeout stops webcam', async () => {
  let deliver;
  const f = fixture({ mediaDevices: { getUserMedia: () => new Promise(resolve => { deliver = resolve; }) } });
  await assert.rejects(f.camera.start(f.video, () => true), { name: 'TimeoutError' });
  deliver(f.stream);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.track.stopCount, 1);
  assert.equal(f.camera.ready, false);
});

test('leaving during permission prompt stops a late stream', async () => {
  let deliver;
  const f = fixture({ mediaDevices: { getUserMedia: () => new Promise(resolve => { deliver = resolve; }) } });
  const pending = f.camera.start(f.video, () => true);
  f.camera.stop();
  await assert.rejects(pending, { name: 'AbortError' });
  deliver(f.stream);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.track.stopCount, 1);
});

test('door changing while encoding blocks completed capture', async () => {
  const f = fixture();
  await f.camera.start(f.video, () => true);
  let checks = 0;
  await assert.rejects(f.camera.capture(f.canvas, () => ++checks === 1), { name: 'DoorOpenError' });
  f.camera.stop();
});

test('disconnect stops stream and reports once', async () => {
  const f = fixture();
  await f.camera.start(f.video, () => true);
  let disconnected = 0;
  f.camera.onDisconnected = () => disconnected++;
  f.track.onended();
  assert.equal(disconnected, 1);
  assert.equal(f.camera.ready, false);
  assert.equal(f.track.onended, null);
});

test('cancelled encoding cannot return an image to a new screen', async () => {
  const f = fixture();
  await f.camera.start(f.video, () => true);
  let encode;
  f.canvas.toBlob = callback => { encode = callback; };
  const pending = f.camera.capture(f.canvas, () => true);
  f.camera.stop();
  await assert.rejects(pending, { name: 'AbortError' });
  encode(new Blob(['late']));
});
