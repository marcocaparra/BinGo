import { registerUser } from "../api/auth.js";
import { setupPasswordToggle } from "../ui/password-toggle.js";

document.addEventListener('DOMContentLoaded', () => {
    setupPasswordToggle('password', 'togglePassword');
});

const step1 = document.getElementById("step1");
const step2 = document.getElementById("step2");
const welcomeName = document.getElementById("welcomeName");
const errorBox = document.getElementById("registerError");

let collectedData = {};

document.getElementById("step1Form").addEventListener("submit", (e) => {
  e.preventDefault();
  collectedData.full_name = document.getElementById("fullName").value.trim();
  collectedData.username = document.getElementById("username").value.trim();

  welcomeName.textContent = `Prazer, ${collectedData.full_name.split(" ")[0]}!`;
  step1.classList.add("hidden");
  step2.classList.remove("hidden");
});

document.getElementById("step2Form").addEventListener("submit", async (e) => {
  e.preventDefault();
  collectedData.cpf = document.getElementById("cpf").value.trim();
  collectedData.phone = document.getElementById("phone").value.trim();
  collectedData.email = document.getElementById("email").value.trim();
  collectedData.password = document.getElementById("password").value.trim();

  try {
    await registerUser(collectedData);
    location.href = "./dashboard.html";
  } catch (err) {
    let message = "Erro ao registrar. Tente novamente.";
    if (err.message.toLowerCase().includes("usuário")) {
      message = "Este nome de usuário já está em uso.";
    } else if (err.message.toLowerCase().includes("email")) {
      message = "Este e-mail já está cadastrado.";
    } else if (err.message.includes("Failed to fetch")) {
      message = "Falha de conexão com o servidor.";
    }
    errorBox.textContent = message;
    errorBox.classList.remove("hidden");
  }
});