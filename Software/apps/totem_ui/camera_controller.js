(function (root) {
  "use strict";

  function cameraError(name, message) {
    return Object.assign(new Error(message), { name });
  }

  function withDeadline(work, signal, timeoutMs) {
    return new Promise((resolve, reject) => {
      const finish = (callback, value) => {
        clearTimeout(timer);
        signal.removeEventListener("abort", abort);
        callback(value);
      };
      const abort = () => finish(reject, cameraError("AbortError", "Camera operation cancelled"));
      const timer = setTimeout(() => finish(reject, cameraError("TimeoutError", "Camera timed out")), timeoutMs);
      signal.addEventListener("abort", abort, { once: true });
      Promise.resolve(work).then(value => finish(resolve, value), error => finish(reject, error));
      if (signal.aborted) abort();
    });
  }

  function waitForFrame(video, signal, timeoutMs) {
    return new Promise((resolve, reject) => {
      const finish = error => {
        clearTimeout(timer);
        video.removeEventListener("loadeddata", ready);
        video.removeEventListener("resize", ready);
        video.removeEventListener("playing", ready);
        video.removeEventListener("error", failed);
        signal.removeEventListener("abort", aborted);
        error ? reject(error) : resolve();
      };
      const ready = () => {
        // Some browsers expose a 2x2 placeholder before the first usable camera frame.
        if (video.readyState >= 2 && video.videoWidth >= 16 && video.videoHeight >= 16) finish();
      };
      const failed = () => finish(cameraError("NotReadableError", "No video frame"));
      const aborted = () => finish(cameraError("AbortError", "Camera operation cancelled"));
      const timer = setTimeout(() => finish(cameraError("TimeoutError", "No video frame")), timeoutMs);
      video.addEventListener("loadeddata", ready);
      video.addEventListener("resize", ready);
      video.addEventListener("playing", ready);
      video.addEventListener("error", failed);
      signal.addEventListener("abort", aborted, { once: true });
      ready();
      if (signal.aborted) aborted();
    });
  }

  class BinGoCamera {
    constructor({ mediaDevices = root.navigator?.mediaDevices, timeoutMs = 15000, waitForVideo = waitForFrame } = {}) {
      this.mediaDevices = mediaDevices;
      this.timeoutMs = timeoutMs;
      this.waitForVideo = waitForVideo;
      this.stream = null;
      this.video = null;
      this.operation = null;
      this.ready = false;
      this.onDisconnected = null;
    }

    assertDoor(isDoorClosed) {
      if (!isDoorClosed()) throw cameraError("DoorOpenError", "Door must be confirmed closed");
    }

    async start(video, isDoorClosed) {
      this.stop();
      this.assertDoor(isDoorClosed);
      if (!this.mediaDevices?.getUserMedia) throw cameraError("NotSupportedError", "Camera requires a supported secure context");
      const operation = new AbortController();
      this.operation = operation;
      this.video = video;
      try {
        // getUserMedia cannot be aborted; release any stream delivered after cancellation.
        const request = this.mediaDevices.getUserMedia({ audio: false, video: { width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 15, max: 24 } } });
        request.then(stream => {
          if (operation.signal.aborted) stream.getTracks().forEach(track => track.stop());
        }, () => {});
        const stream = await withDeadline(request, operation.signal, this.timeoutMs);
        this.stream = stream;
        this.assertDoor(isDoorClosed);
        video.srcObject = stream;
        await withDeadline(video.play(), operation.signal, this.timeoutMs);
        await this.waitForVideo(video, operation.signal, this.timeoutMs);
        this.assertDoor(isDoorClosed);
        if (operation.signal.aborted || this.operation !== operation) throw cameraError("AbortError", "Stale camera operation");
        this.ready = true;
        stream.getVideoTracks().forEach(track => {
          track.onended = () => {
            if (this.operation !== operation) return;
            this.stop();
            this.onDisconnected?.();
          };
        });
      } catch (error) {
        if (this.operation === operation) this.stop();
        throw error;
      }
    }

    async capture(canvas, isDoorClosed) {
      this.assertDoor(isDoorClosed);
      if (!this.ready || !this.stream?.getVideoTracks().some(track => track.readyState === "live")) {
        throw cameraError("NotReadableError", "Camera is not ready");
      }
      const video = this.video;
      if (video.videoWidth < 16 || video.videoHeight < 16 || video.readyState < 2) throw cameraError("NotReadableError", "Empty frame");
      const operation = this.operation;
      const scale = Math.min(1, 1280 / video.videoWidth, 960 / video.videoHeight);
      canvas.width = Math.round(video.videoWidth * scale);
      canvas.height = Math.round(video.videoHeight * scale);
      const context = canvas.getContext("2d");
      if (!context) throw cameraError("NotReadableError", "Canvas unavailable");
      context.drawImage(video, 0, 0, canvas.width, canvas.height);
      const blob = await withDeadline(new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", 0.85)), operation.signal, this.timeoutMs);
      this.assertDoor(isDoorClosed);
      if (this.operation !== operation) throw cameraError("AbortError", "Stale capture");
      if (!blob?.size) throw cameraError("NotReadableError", "Empty capture");
      return { blob, width: canvas.width, height: canvas.height, capturedAt: new Date().toISOString() };
    }

    stop() {
      this.operation?.abort();
      this.operation = null;
      this.ready = false;
      this.stream?.getTracks().forEach(track => { track.onended = null; track.stop(); });
      this.stream = null;
      if (this.video) this.video.srcObject = null;
      this.video = null;
    }
  }

  root.BinGoCamera = BinGoCamera;
  if (typeof module !== "undefined" && module.exports) module.exports = { BinGoCamera };
})(globalThis);
