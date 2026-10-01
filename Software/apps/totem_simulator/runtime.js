(function (root) {
  "use strict";
  function resolveRuntime(mode = "local", location = {}) {
    if (mode === "cloud")
      return Object.freeze({ mode, baseUrl: "", visionUrl: "/vision/analyze" });
    if (mode !== "local") throw new Error("Invalid simulator runtime mode");
    const baseUrl = "http://127.0.0.1:8765";
    const override = new URLSearchParams(location.search || "").get(
      "visionUrl",
    );
    const vision = new URL(override || `${baseUrl}/vision/analyze`);
    if (
      !["http:", "https:"].includes(vision.protocol) ||
      !["127.0.0.1", "localhost"].includes(vision.hostname) ||
      vision.username ||
      vision.password ||
      vision.search ||
      vision.hash
    )
      throw new Error("Vision override must use loopback in local mode.");
    return Object.freeze({ mode, baseUrl, visionUrl: vision.href });
  }
  root.BinGoRuntime = resolveRuntime(
    root.BinGoRuntimeMode || "local",
    root.location,
  );
  if (typeof module !== "undefined" && module.exports)
    module.exports = { resolveRuntime };
})(globalThis);
