/**
 * Loader fullscreen baseado em .is-visible
 * - refcount (show/hide) para várias requisições
 * - mínimo visível de 2s para não "piscar"
 * - hardShow() para navegação/refresh
 */
const root = document.getElementById("pageLoader");
const MIN_SHOW_MS = 2000;   // 2s
const MIN_HIDE_MS = 180;    // suaviza fade-out

let refCount = 0;
let shownAt = 0;
let hideTimer = null;

function present(){ return !!root; }
function reallyShow(){
  if (!present()) return;
  root.classList.add("is-visible");
  shownAt = performance.now();
}
function reallyHide(){
  if (!present()) return;
  root.classList.remove("is-visible");
}

function show(){
  if (!present()) return;
  if (hideTimer){ clearTimeout(hideTimer); hideTimer = null; }
  if (refCount === 0) { reallyShow(); }
  refCount++;
}

function hide(){
  if (!present()) return;
  refCount = Math.max(0, refCount - 1);
  if (refCount > 0) return;

  const elapsed = performance.now() - shownAt;
  const wait = Math.max(0, MIN_SHOW_MS - elapsed);

  hideTimer = setTimeout(() => {
    reallyHide();
    hideTimer = null;
  }, wait + MIN_HIDE_MS);
}

function hardShow(){
  if (!present()) return;
  refCount = 0;
  show();
}

export default { show, hide, hardShow };
