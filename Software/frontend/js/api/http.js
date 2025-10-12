// public/js/api/http.js
import { apiBaseUrl, STORAGE_KEYS } from "../config.js";

function buildUrl(path) {
  const base = apiBaseUrl();            // garante sem barra no final
  const clean = String(path || "").trim();
  if (!clean.startsWith("/")) return `${base}/${clean}`;
  return `${base}${clean}`;
}

export async function apiFetch(path, { method = "GET", headers, body } = {}) {
  const url = buildUrl(path);
  const token = localStorage.getItem(STORAGE_KEYS.token);

  const finalHeaders = new Headers({
    "Accept": "application/json",
    "Content-Type": "application/json",
    ...headers,
  });

  if (token) finalHeaders.set("Authorization", `Bearer ${token}`);

  // DEBUG: loga a requisição
  // (se preferir, comente após validar)
  console.debug("[apiFetch] →", method, url, { body });

  let res;
  try {
    res = await fetch(url, {
      method,
      headers: finalHeaders,
      body,
      mode: "cors",
      credentials: "omit"
    });
  } catch (e) {
    console.error("[apiFetch] Network error:", e);
    throw new Error("Falha de rede ao contactar o backend");
  }

  // DEBUG: status
  console.debug("[apiFetch] ←", res.status, res.statusText, url);

  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try {
      const data = await res.json();
      if (data?.detail) msg += ` – ${data.detail}`;
    } catch (_) { /* ignore */ }
    throw new Error(msg);
  }

  // 204/205 não têm corpo
  if (res.status === 204 || res.status === 205) return null;

  // tenta JSON, se não for, devolve texto
  const ct = res.headers.get("content-type") || "";
  if (ct.includes("application/json")) return res.json();
  return res.text();
}
