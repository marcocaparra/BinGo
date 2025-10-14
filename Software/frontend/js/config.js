export function apiBaseUrl() {
  const meta = document.querySelector('meta[name="api-base-url"]')?.content?.trim();
  const fromWindow = window.__API_BASE_URL__;
  const stored = localStorage.getItem("API_BASE_URL");

  const base = fromWindow || meta || stored || "http://localhost:8000/";
  return String(base).replace(/\/+$/, "");
}

export const STORAGE_KEYS = {
  token: "authToken",
  user: "authUser",
};
