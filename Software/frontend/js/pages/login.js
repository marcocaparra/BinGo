import { login } from "../api/auth.js";

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
    errorBox.textContent = err.message || "Erro ao fazer login";
    errorBox.classList.remove("hidden");
  }
});
