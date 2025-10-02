import { getMe, logout, requireAuth } from "../api/auth.js";

export async function bootDashboard() {
  requireAuth();

  const userNameEl = document.getElementById("userName");
  const userBinsEl = document.getElementById("userBins");
  const userLevelEl = document.getElementById("userLevel");
  const logoutBtn = document.getElementById("logout");

  logoutBtn?.addEventListener("click", () => {
    logout();
  });

  try {
    const me = await getMe();
    
    const firstName = (me.name || me.username || "Herói").split(" ")[0];
    userNameEl.textContent = firstName;

    userBinsEl.textContent = me.total_points ?? 0;

    const levelNames = {
      1: "Semeador",
      2: "Plantador",
      3: "Cuidador",
      4: "Guardião",
      5: "Mestre Verde"
    };

    const levelNum = me.level ?? 1;
    userLevelEl.textContent = levelNames[levelNum] || `Nível ${levelNum}`;

    console.log("Dashboard carregado:", me);
  } catch (err) {
    console.error("Erro ao carregar perfil:", err);
    alert("Falha ao carregar dados do usuário. Faça login novamente.");
    logout();
  }
}

bootDashboard();
