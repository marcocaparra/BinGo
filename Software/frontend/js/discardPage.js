import { registerDiscard } from "../js/api/discard.js";
import { getMe, requireAuth } from "../js/api/auth.js";

requireAuth();

const discardSection = document.getElementById("discard-section");
const successSection = document.getElementById("success-section");
const errorSection = document.getElementById("error-section");

const input = document.getElementById("discardCode");
const button = document.getElementById("discardBtn");
const feedback = document.getElementById("feedback");
const bingolinoImg = document.getElementById("bingolino-img");
const tryAgainBtn = document.getElementById("tryAgainBtn");
const backBtn = document.getElementById("backBtn");

const userLevelEl = document.getElementById("userLevel");
const userPointsEl = document.getElementById("userPoints");

console.log("🟢 discardPage.js carregado");

backBtn.addEventListener("click", () => history.back());

tryAgainBtn?.addEventListener("click", () => {
  errorSection.classList.add("hidden");
  discardSection.classList.remove("hidden");
  input.value = "";
  feedback.classList.add("hidden");
  bingolinoImg.src = "../assets/images/bingolino-discard.png";
});

button.addEventListener("click", async () => {
  feedback.classList.add("hidden");
  
  const code = input.value.trim();
  if (!code) {
    showError("Por favor, digite um código.");
    return;
  }

  try {
    await registerDiscard(code);
    const me = await getMe();

    const levelNames = {
      1: "Semeador",
      2: "Plantador",
      3: "Cuidador",
      4: "Guardião",
      5: "Mestre Verde"
    };

    const levelNum = me.level ?? 1;
    userLevelEl.textContent = levelNames[levelNum] || `Nível ${levelNum}`;
    userPointsEl.textContent = me.total_points ?? 0;

    discardSection.classList.add("hidden");
    successSection.classList.remove("hidden");

  } catch (err) {
    console.warn("Erro ao validar:", err);
    discardSection.classList.add("hidden");
    errorSection.classList.remove("hidden");
  }
});

function showError(msg) {
  feedback.textContent = msg;
  feedback.classList.remove("hidden");
}