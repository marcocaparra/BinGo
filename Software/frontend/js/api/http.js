import { apiBaseUrl, STORAGE_KEYS } from "../config.js";

function buildUrl(path) {
  const base = apiBaseUrl();
  if (/^https?:\/\//i.test(path)) return path;
  return `${base}${path.startsWith("/") ? "" : "/"}${path}`;
}

export async function apiFetch(path, options = {}) {
  const token = localStorage.getItem(STORAGE_KEYS.token);
  const headers = new Headers(options.headers || {});

  if (!headers.has("Content-Type") && !(options.body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
  }
  if (token) headers.set("Authorization", `Bearer ${token}`);

  console.log("➡️ Fetch:", buildUrl(path));

  const res = await fetch(buildUrl(path), { ...options, headers });

  let data = null;
  const text = await res.text();
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }

  if (!res.ok) {
    const msg = data?.detail || data?.message || `Erro HTTP ${res.status}`;
    throw new Error(msg);
  }
  return data;
}
