(function (root) {
  "use strict";

  const VisionResult = Object.freeze({
    RECOGNIZED: "recognized",
    NEEDS_SECONDARY: "needs-secondary",
    REJECTED: "rejected",
  });

  const VisionStage = Object.freeze({
    PRIMARY: "primary",
    SECONDARY: "secondary",
  });

  const VisionOrigin = Object.freeze({
    PRIMARY: "VISION_PRIMARY",
    SECONDARY: "VISION_SECONDARY",
    REKOGNITION: "AWS_REKOGNITION",
    GEMINI: "GEMINI_FALLBACK",
    MANUAL: "MANUAL_REVIEW",
  });

  function visionError(name, message) {
    return Object.assign(new Error(message), { name });
  }

  function wait(delayMs, signal) {
    return new Promise((resolve, reject) => {
      const finish = (callback, value) => {
        clearTimeout(timer);
        signal?.removeEventListener("abort", abort);
        callback(value);
      };
      const abort = () => finish(reject, visionError("AbortError", "Vision analysis cancelled"));
      const timer = setTimeout(() => finish(resolve), delayMs);
      signal?.addEventListener("abort", abort, { once: true });
      if (signal?.aborted) abort();
    });
  }

  function normalizeResult(raw, stage) {
    if (!raw || !Object.values(VisionResult).includes(raw.status)) {
      throw visionError("InvalidVisionResponseError", "Invalid vision response status");
    }
    if (raw.status === VisionResult.RECOGNIZED && typeof raw.itemId !== "string") {
      throw visionError("InvalidVisionResponseError", "Recognized result requires an item id");
    }
    return Object.freeze({
      status: raw.status,
      itemId: raw.itemId ?? null,
      candidateIds: Array.isArray(raw.candidateIds) ? [...new Set(raw.candidateIds)] : [],
      confidence: Number.isFinite(raw.confidence) ? Math.max(0, Math.min(1, raw.confidence)) : null,
      origin: raw.origin ?? (stage === VisionStage.SECONDARY ? VisionOrigin.SECONDARY : VisionOrigin.PRIMARY),
    });
  }

  class CascadingVisionProvider {
    constructor({ rekognitionProvider, geminiProvider, fallbackThreshold = 0.75 } = {}) {
      if (!rekognitionProvider?.analyze || !geminiProvider?.analyze) {
        throw visionError(
          "VisionIntegrationUnavailableError",
          "Rekognition and Gemini adapters are required for the real vision cascade",
        );
      }
      this.rekognitionProvider = rekognitionProvider;
      this.geminiProvider = geminiProvider;
      this.fallbackThreshold = Math.max(0, Math.min(1, fallbackThreshold));
    }

    async analyze({ stage = VisionStage.PRIMARY, ...request } = {}) {
      const secondary = stage === VisionStage.SECONDARY;
      const adapter = secondary ? this.geminiProvider : this.rekognitionProvider;
      const origin = secondary ? VisionOrigin.GEMINI : VisionOrigin.REKOGNITION;
      const result = normalizeResult(await adapter.analyze({ ...request, stage }), stage);

      if (!secondary && result.status === VisionResult.RECOGNIZED
        && (result.confidence === null || result.confidence < this.fallbackThreshold)) {
        return normalizeResult({
          status: VisionResult.NEEDS_SECONDARY,
          candidateIds: [result.itemId, ...result.candidateIds].filter(Boolean),
          confidence: result.confidence,
          origin,
        }, stage);
      }

      return normalizeResult({ ...result, origin }, stage);
    }
  }

  class MockVisionProvider {
    constructor({ primaryDelayMs = 2400, secondaryDelayMs = 2600 } = {}) {
      this.primaryDelayMs = primaryDelayMs;
      this.secondaryDelayMs = secondaryDelayMs;
    }

    async analyze({ frame, stage = VisionStage.PRIMARY, scenario = "success", signal } = {}) {
      if (!frame?.simulated && !frame?.blob) {
        throw visionError("MissingVisionFrameError", "A captured frame is required");
      }
      await wait(stage === VisionStage.SECONDARY ? this.secondaryDelayMs : this.primaryDelayMs, signal);

      if (stage === VisionStage.SECONDARY) {
        return normalizeResult({
          status: VisionResult.RECOGNIZED,
          itemId: "cable",
          candidateIds: ["cable", "battery", "small"],
          confidence: 0.76,
          origin: VisionOrigin.SECONDARY,
        }, stage);
      }
      if (scenario === "rejected") {
        return normalizeResult({ status: VisionResult.REJECTED, confidence: 0.18 }, stage);
      }
      if (scenario === "uncertain") {
        return normalizeResult({
          status: VisionResult.NEEDS_SECONDARY,
          candidateIds: ["cable", "small", "phone"],
          confidence: 0.48,
        }, stage);
      }
      return normalizeResult({
        status: VisionResult.RECOGNIZED,
        itemId: "cable",
        candidateIds: ["cable", "small", "phone"],
        confidence: 0.93,
      }, stage);
    }
  }

  class RemoteVisionProvider {
    constructor({ endpoint, edgeKey = "", fetchImpl = (...args) => root.fetch(...args) } = {}) {
      if (!endpoint || typeof fetchImpl !== "function") {
        throw visionError("VisionIntegrationUnavailableError", "A remote vision endpoint is required");
      }
      this.endpoint = endpoint;
      this.edgeKey = edgeKey;
      this.fetchImpl = fetchImpl;
      this.lastCandidateIds = [];
    }

    async analyze({ frame, stage = VisionStage.PRIMARY, signal } = {}) {
      if (!frame?.blob) throw visionError("MissingVisionFrameError", "A captured frame is required");
      const headers = { "Content-Type": frame.blob.type || "image/jpeg" };
      if (this.edgeKey) headers["X-BinGo-Edge-Key"] = this.edgeKey;
      const query = new URLSearchParams({ stage });
      if (stage === VisionStage.SECONDARY && this.lastCandidateIds.length) {
        query.set("candidates", this.lastCandidateIds.join(","));
      }
      const response = await this.fetchImpl(`${this.endpoint}?${query}`, {
        method: "POST",
        headers,
        body: frame.blob,
        signal,
      });

      if (response.status === 501 && stage === VisionStage.SECONDARY) {
        return normalizeResult({
          status: VisionResult.RECOGNIZED,
          itemId: "unknown",
          candidateIds: this.lastCandidateIds,
          confidence: 0,
          origin: VisionOrigin.MANUAL,
        }, stage);
      }
      if (!response.ok) {
        let details = {};
        try {
          details = await response.json();
        } catch (_error) {
          // The status remains enough to present a safe operational failure.
        }
        const error = visionError("VisionServiceError", `Vision service returned ${response.status}`);
        error.provider = details.provider ?? "VISION_CASCADE";
        throw error;
      }
      const result = normalizeResult(await response.json(), stage);
      if (stage === VisionStage.PRIMARY) this.lastCandidateIds = result.candidateIds;
      return result;
    }
  }

  function createVisionProvider(options = {}) {
    const { remoteUrl, edgeKey, fetchImpl, rekognitionProvider, geminiProvider, fallbackThreshold, ...mockOptions } = options;
    if (remoteUrl) return new RemoteVisionProvider({ endpoint: remoteUrl, edgeKey, fetchImpl });
    if (rekognitionProvider || geminiProvider) {
      return new CascadingVisionProvider({ rekognitionProvider, geminiProvider, fallbackThreshold });
    }
    return new MockVisionProvider(mockOptions);
  }

  root.BinGoVision = {
    VisionResult,
    VisionStage,
    VisionOrigin,
    CascadingVisionProvider,
    MockVisionProvider,
    RemoteVisionProvider,
    createVisionProvider,
    normalizeResult,
  };
  if (typeof module !== "undefined" && module.exports) {
    module.exports = root.BinGoVision;
  }
})(globalThis);
