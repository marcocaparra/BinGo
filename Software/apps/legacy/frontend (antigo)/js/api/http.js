import { apiBaseUrl, STORAGE_KEYS } from "../config.js";
import loader from "../ui/loader.js";

function buildUrl(path) {
  const base = apiBaseUrl();
  const clean = String(path || "").trim();
  return clean.startsWith("/") ? `${base}${clean}` : `${base}/${clean}`;
}

let activeRequests = 0;
let hideTimer = null;
const MIN_LOADER_MS = 2000;
let firstShownAt = 0;

function showLoaderIfNeeded(message) {
  if (hideTimer) {
    clearTimeout(hideTimer);
    hideTimer = null;
  }
  if (activeRequests === 0) {
    firstShownAt = performance.now();
    try {
      if (typeof loader.setMinVisible === "function") {
        loader.setMinVisible(MIN_LOADER_MS);
      }
    } catch {}
    loader.show(message);
  }
  activeRequests++;
}

function hideLoaderIfNeeded() {
  activeRequests = Math.max(0, activeRequests - 1);
  if (activeRequests === 0) {
    const elapsed = performance.now() - firstShownAt;
    const wait = Math.max(0, MIN_LOADER_MS - elapsed);
    hideTimer = setTimeout(() => {
      loader.hide();
      hideTimer = null;
    }, wait);
  }
}

/**
 * apiFetch
 * @param {string} path
 * @param {object} opts
 *   - method, headers, body (obj auto-JSON)
 *   - noLoader: boolean
 *   - loaderMessage: string
 *   - timeoutMs: number (padrão 15000)
 */
export async function apiFetch(
  path,
  { method = "GET", headers, body, noLoader = false, loaderMessage, timeoutMs = 15000 } = {}
) {
  const url = buildUrl(path);
  const token = localStorage.getItem(STORAGE_KEYS.token);

  const finalHeaders = new Headers({
    Accept: "application/json",
    ...(body instanceof FormData ? {} : { "Content-Type": "application/json" }),
    ...headers,
  });
  if (token) finalHeaders.set("Authorization", `Bearer ${token}`);

  let requestBody = body;
  if (body && typeof body === "object" && !(body instanceof FormData)) {
    requestBody = JSON.stringify(body);
    if (!finalHeaders.has("Content-Type")) {
      finalHeaders.set("Content-Type", "application/json");
    }
  }

  if (!noLoader) showLoaderIfNeeded(loaderMessage);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  console.debug("[apiFetch] →", method, url, { body: requestBody });

  let res;
  try {
    res = await fetch(url, {
      method,
      headers: finalHeaders,
      body: requestBody,
      mode: "cors",
      credentials: "omit",
      signal: controller.signal,
    });
  } catch (e) {
    if (e.name === "AbortError") {
      throw new Error("Tempo limite excedido. Tente novamente.");
    }
    console.error("[apiFetch] Network error:", e);
    throw new Error("Falha de rede ao contactar o backend");
  } finally {
    clearTimeout(timeout);
    if (!noLoader) hideLoaderIfNeeded();
  }

  console.debug("[apiFetch] ←", res.status, res.statusText, url);

  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try {
      const data = await res.json();
      if (data?.detail) msg += ` – ${data.detail}`;
    } catch (_) { /* ignore */ }
    throw new Error(msg);
  }

  if (res.status === 204 || res.status === 205) return null;

  const ct = (res.headers.get("content-type") || "").toLowerCase();
  if (ct.includes("application/json")) return res.json();
  return res.text();
}
