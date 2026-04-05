import { login } from "../api/auth.js";
import { setupPasswordToggle } from "../ui/password-toggle.js";

document.addEventListener('DOMContentLoaded', () => {
    setupPasswordToggle('password', 'togglePassword');
});

const form = document.getElementById("loginForm");
const errorBox = document.getElementById("error");

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const username = document.getElementById("username").value.trim();
  const password = document.getElementById("password").value.trim();

  try {
    await login(username, password);
    location.href = "./dashboard.html";
  } catch (err) {
    let message = "Erro ao fazer login. Tente novamente.";
    if (err.message.includes("401")) {
      message = "Usuário ou senha incorretos.";
    } else if (err.message.includes("Failed to fetch")) {
      message = "Falha de conexão com o servidor. Verifique sua internet.";
    }
    errorBox.textContent = message;
    errorBox.classList.remove("hidden");
  }
});