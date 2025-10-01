import { getMe, logout, requireAuth } from "../api/auth.js";

export async function bootDashboard() {
  requireAuth();

  const welcome = document.getElementById("welcome");
  const points = document.getElementById("points");
  const logoutBtn = document.getElementById("logout");
  const discardBtn = document.getElementById("goDiscard");

  logoutBtn?.addEventListener("click", () => {
    logout();
  });

  discardBtn?.addEventListener("click", () => {
    alert("🚧 Em breve: fluxo de descarte!");
  });

  try {
    const me = await getMe();
    welcome.textContent = `Olá, ${me.name || me.username}!`;
    points.textContent = me.total_points ?? 0;
  } catch (err) {
    console.error("Erro ao carregar perfil:", err);
    alert("Falha ao carregar dados do usuário. Faça login novamente.");
    logout();
  }
}
