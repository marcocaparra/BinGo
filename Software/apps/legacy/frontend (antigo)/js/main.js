export function toast(msg){
  const el = document.getElementById("toast");
  if (!el) return;
  el.textContent = msg; el.classList.remove("hidden");
  setTimeout(()=> el.classList.add("hidden"), 2500);
}
export function qs(sel){ return document.querySelector(sel); }
