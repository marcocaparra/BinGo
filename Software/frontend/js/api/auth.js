import { apiBaseUrl, STORAGE_KEYS } from "../config.js";
import { apiFetch } from "./http.js";

export async function login(username, password) {
  const res = await fetch(`${apiBaseUrl()}/users/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password })
  });

  if (!res.ok) throw new Error(`Falha no login: ${res.status}`);

  const data = await res.json();
  const token = data?.access_token;
  if (!token) throw new Error("Resposta sem token");

  localStorage.setItem(STORAGE_KEYS.token, token);

  try {
    const me = await getMe();
    localStorage.setItem(STORAGE_KEYS.user, JSON.stringify(me));
  } catch (err) {
    console.warn("Login ok mas falhou ao buscar /me:", err);
  }

  return true;
}

export async function registerUser({ username, email, password, full_name, cpf, phone }) {
  await apiFetch("/users/", {
    method: "POST",
    body: JSON.stringify({
      username,
      email,
      password,
      name: full_name,
      cpf: cpf || null,
      phone_number: phone || null,
      total_points: 0
    })
  });

  await login(username, password);
}

export async function getMe() {
  return apiFetch("/users/me/", { method: "GET" });
}

export function logout() {
  localStorage.removeItem(STORAGE_KEYS.token);
  localStorage.removeItem(STORAGE_KEYS.user);
  location.href = "./login.html";
}

export function requireAuth() {
  const token = localStorage.getItem(STORAGE_KEYS.token);
  if (!token) location.href = "./login.html";
}
