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
    
    // Nome
    const firstName = (me.name || me.username || "Herói").split(" ")[0];
    userNameEl.textContent = firstName;

    // Pontos (Bins)
    userBinsEl.textContent = me.total_points ?? 0;

    // Mapeamento de níveis (visual)
    const levelNames = {
      1: "Semeador",
      2: "Plantador",
      3: "Cuidador",
      4: "Guardião",
      5: "Mestre Verde"
    };

    // Se o backend mandar um nível que não está no mapa, mostra o número mesmo
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
