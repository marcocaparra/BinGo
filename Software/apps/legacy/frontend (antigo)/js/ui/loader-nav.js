import loader from "./loader.js";

/* Esconde quando a página terminou de carregar (respeita mínimo no loader.js) */
window.addEventListener("load", () => loader.hide());
window.addEventListener("pageshow", () => loader.hide());

/* Mostra ao clicar em links internos (mesma origem) */
document.addEventListener("click", (e) => {
  const a = e.target.closest("a[href]");
  if (!a) return;
  if (a.target && a.target !== "" && a.target !== "_self") return;

  const url = new URL(a.href, location.href);
  if (url.origin !== location.origin) return;

  loader.hardShow();
});

/* Fallback: F5 / navegação fora */
window.addEventListener("beforeunload", () => loader.hardShow());
