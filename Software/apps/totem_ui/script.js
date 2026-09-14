const assets = {
  logo: "./assets/brand/logo_bingo_sem_slogan.png",
  b1n: "./assets/characters/b1n_joinha_confirmacao_web.png",
  b1nCorner: "./assets/characters/b1n_joinha_confirmacao_corner_norm_web.png",
  b1nDoubtCorner: "./assets/characters/b1n_duvida_pergunta_corner_norm_web.png",
  b1nIdea: "./assets/characters/b1n_ideia_instrucao_web.png",
  b1nIdeaCorner: "./assets/characters/b1n_ideia_instrucao_corner_norm_web.png",
  b1nPrivacyCorner: "./assets/characters/b1n_privacidade_pin_olhos_fechados_corner_norm_web.png",
  b1nPrivacy: "./assets/characters/b1n_privacidade_pin_olhos_fechados_web.png",
  b1nSleep: "./assets/characters/b1n_dormindo_kiosk_idle_clean_web.png",
  b1nPointLeft: "./assets/characters/b1n_apontando_esquerda_compartimento_web.png",
  b1nAnalyze: "./assets/characters/b1n_lupa_analise_web.png",
  b1nReward: "./assets/characters/b1n_segurando_bincoin_recompensa_web.png",
  detectedCable: "./assets/items/descarte_cabo_usb_web.png",
};

const schoolTree = {
  fundamental1: {
    label: "Fund. 1",
    speech: "Legal. Agora escolha o ano.",
    years: ["1º Ano", "2º Ano", "3º Ano", "4º Ano", "5º Ano"],
  },
  fundamental2: {
    label: "Fund. 2",
    speech: "Legal. Agora escolha o ano.",
    years: ["6º Ano", "7º Ano", "8º Ano", "9º Ano"],
  },
  medio: {
    label: "Ensino Médio",
    speech: "Legal. Agora escolha a série.",
    years: ["1ª Série", "2ª Série", "3ª Série"],
  },
};

const classLetters = ["A", "B", "C", "D"];

const students = [
  "Ana Clara M.",
  "Arthur S.",
  "Bianca R.",
  "Bruno P.",
  "Camila F.",
  "Davi L.",
  "Eduarda C.",
  "Gabriel N.",
  "Giovana A.",
  "Guilherme A.",
  "Gustavo B.",
  "Helena T.",
  "João P.",
  "Laura V.",
  "Lucas M.",
  "Marco C.",
  "Maria E.",
  "Miguel R.",
  "Pedro H.",
  "Rafaela S.",
];

const keyboardRows = [
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ç"],
  ["z", "x", "c", "v", "b", "n", "m"],
];

const screens = [
  {
    id: "sleep",
    label: "Descanso",
    render: () => `
      <section class="screen screen--sleep is-sleep" data-next="idle">
        <img class="sleep-logo" src="${assets.logo}" alt="BinGo" />
        <div class="content-zone content-zone--sleep">
          <div class="sleeping-b1n">
            <img src="${assets.b1nSleep}" alt="B1N dormindo enquanto aguarda toque" />
            <div class="zzz-group" aria-hidden="true"><span>Z</span><span>z</span><span>z</span></div>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action wake-action" data-next="idle">Toque para começar</button>
        </div>
      </section>
    `,
  },
  {
    id: "idle",
    label: "Início",
    render: () => `
      <section class="screen screen--big screen--stack-action is-idle">
        ${topbar("Pronto")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1n, "Trouxe eletrônico? Eu te guio.", "big welcome-talk character-joinha")}
        </div>
        <div class="action-zone action-zone--stack action-zone--single">
          <button class="primary-action wake-action" data-next>Descartar agora</button>
        </div>
      </section>
    `,
  },
  {
    id: "identity",
    label: "Participar",
    render: () => `
      <section class="screen screen--big screen--stack-action">
        ${topbar("Participar")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1n, "Como quer participar?", "big character-joinha")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-mode="student" data-next>Quero BinCoins</button>
          <button class="secondary-action" data-mode="classOnly" data-next>Só pontuar pra turma</button>
        </div>
      </section>
    `,
  },
  {
    id: "segment",
    label: "Segmento",
    render: () => `
      <section class="screen screen--corner screen--no-action screen--choice-list">
        ${topbar("Segmento")}
        <div class="content-zone content-zone--corner">
          ${talk(assets.b1nCorner, "Toque no seu segmento.", "corner")}
          <div class="option-stack">
            ${Object.entries(schoolTree).map(([id, segment]) => `
              <button class="list-button list-button--large" data-segment="${id}" data-next>
                <span>${segment.label}</span>${arrowIcon("right")}
              </button>
            `).join("")}
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "year",
    label: "Ano",
    render: () => {
      const segment = schoolTree[selectedSegment] ?? schoolTree.fundamental2;
      return `
        <section class="screen screen--corner screen--no-action screen--choice-list">
          ${topbar("Ano")}
          <div class="content-zone content-zone--corner">
            ${talk(assets.b1nCorner, segment.speech, "corner")}
            <div class="list year-list">
              ${segment.years.map((year) => `
                <button class="list-button" data-year="${year}" data-next>
                  <span>${year}</span>${arrowIcon("right")}
                </button>
              `).join("")}
            </div>
          </div>
        </section>
      `;
    },
  },
  {
    id: "class",
    label: "Turma",
    render: () => `
      <section class="screen screen--corner screen--no-action compact-screen">
        ${topbar("Turma")}
        <div class="content-zone content-zone--corner">
          ${talk(assets.b1nCorner, "Agora escolha a turma.", "corner")}
          <div class="list class-list">
            ${classLetters.map((letter) => `
              <button class="list-button" data-class="${letter}" data-next="${flowMode === "classOnly" ? "insert" : ""}">
                <span>${selectedYear ?? "Ano"} ${letter}</span>${arrowIcon("right")}
              </button>
            `).join("")}
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "student",
    label: "Aluno",
    render: () => `
      <section class="screen screen--student screen--no-action ${searchActive || keyboardClosing ? "is-searching" : ""} ${keyboardClosing ? "is-keyboard-closing" : ""}" data-search-screen>
        ${topbar("Aluno")}
        <div class="student-layout">
          ${talk(assets.b1nDoubtCorner, "Busque ou escolha seu nome.", "corner student-guide")}
          <div class="search-box ${searchActive ? "active" : ""} ${searchQuery ? "has-value" : ""}" data-search-toggle aria-label="Busca de aluno">
            <span class="${!searchQuery ? "search-placeholder" : ""}">${searchQuery || "Digite seu nome..."}</span>
            <button class="clear-search" data-key="clear" aria-label="Limpar busca">×</button>
          </div>
          <div class="student-list">
            ${filteredStudents().map((name) => `
              <button class="list-button student-button" data-student="${name}" data-next>
                <span>${name}</span>${arrowIcon("right")}
              </button>
            `).join("") || `<div class="empty-state">Não achei esse nome. Tente apagar uma letra.</div>`}
          </div>
          ${searchActive || keyboardClosing ? visualKeyboard() : ""}
        </div>
      </section>
    `,
  },
  {
    id: "pin",
    label: "PIN",
    render: () => `
      <section class="screen screen--corner screen--pin screen--with-cancel">
        ${topbar("PIN", { back: false })}
        <div class="content-zone content-zone--corner content-zone--pin">
          ${talk(assets.b1nPrivacyCorner, "Digite seu PIN. Eu não olho.", "corner privacy-guide character-privacy")}
          <div class="pin-display">
            ${[0, 1, 2, 3].map((index) => `<span class="pin-dot ${index < pinDigits ? "filled" : ""}"></span>`).join("")}
          </div>
          <div class="pin-pad">
            ${["1", "2", "3", "4", "5", "6", "7", "8", "9", "Apagar", "0", "OK"].map((key) => `
              <button class="key ${["Apagar", "OK"].includes(key) ? "key-action" : ""} ${key === "OK" && pinDigits < 4 ? "key-disabled" : ""}" data-pin="${key}" ${key === "OK" && pinDigits < 4 ? "disabled" : ""}>${key}</button>
            `).join("")}
          </div>
          <div class="pin-hint ${pinWarning ? "show" : ""}">Digite 4 números.</div>
        </div>
        <div class="action-zone action-zone--cancel">
          <button class="cancel-action" data-cancel-discard>Cancelar descarte</button>
        </div>
      </section>
    `,
  },
  {
    id: "insert",
    label: "Inserir",
    render: () => `
      <section class="screen screen--big screen--insert">
        ${topbar("Abertura")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1nPointLeft, "Coloque o item na abertura à esquerda.", "big insert-talk character-point-left")}
          <div class="insert-visual" aria-hidden="true">
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-next="safety">Pronto, coloquei</button>
        </div>
      </section>
    `,
  },
  {
    id: "safety",
    label: "Segurança",
    render: () => `
      <section class="screen screen--corner screen--safety screen--stack-action">
        ${topbar("Segurança")}
        <div class="content-zone content-zone--corner content-zone--safety">
          ${talk(assets.b1nIdeaCorner, "Antes de fechar: segurança primeiro.", "corner safety-guide")}
          <div class="safety-card">
            <strong>Confirme comigo</strong>
            <div class="safety-row"><span>1</span><p>Minha mão está fora da abertura.</p></div>
            <div class="safety-row"><span>2</span><p>O item não está vazando nem estufado.</p></div>
            <p class="safety-note">Se o item estiver vazando ou estufado, chame um professor.</p>
          </div>
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-next="camera">Tudo seguro</button>
          <button class="alert-action" data-jump="teacher">Chamar professor</button>
        </div>
      </section>
    `,
  },
  {
    id: "camera",
    label: "Câmera",
    render: () => `
      <section class="screen screen--camera screen--auto" data-auto-next="ai-feedback">
        ${topbar("Câmera", { back: false })}
        <div class="content-zone content-zone--camera">
          ${talk(assets.b1nAnalyze, "Vou olhar por dentro rapidinho.", "big camera-talk character-analyze")}
          <div class="camera-preview" aria-label="Preview da câmera interna">
            <div class="camera-bar"><span>Câmera interna</span><strong>AO VIVO</strong></div>
            <div class="camera-frame">
              <div class="scan-line"></div>
              <span class="camera-label">Item sendo identificado...</span>
            </div>
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "ai-feedback",
    label: "IA",
    render: () => `
      <section class="screen screen--ai screen--stack-action">
        ${topbar("IA")}
        <div class="content-zone content-zone--ai">
          ${talk(assets.b1nAnalyze, "Detectei um cabo pequeno. Acertei?", "big ai-talk character-analyze")}
          <div class="ai-card">
            <img src="${assets.detectedCable}" alt="" />
            <div>
              <strong>1 cabo ou carregador</strong>
              <div class="ai-rewards">
                <span class="reward-gradient"><b>+800</b> BinCoins</span>
                <span class="team-reward"><b>+1</b> ponto para a turma</span>
              </div>
            </div>
          </div>
        </div>
        <div class="action-zone action-zone--ai">
          <button class="primary-action" data-next="success">Sim, continuar</button>
          <div class="split-actions">
            <button class="secondary-action" data-jump="teacher">Não é isso</button>
            <button class="secondary-action" data-jump="teacher">Quantidade errada</button>
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "success",
    label: "Resultado",
    render: () => `
      <section class="screen screen--big screen--success">
        ${topbar("Concluído")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1nReward, "Boa! +800 BinCoins pra você.", "big character-reward")}
          <div class="reward-card">
            <div class="metric metric--you"><span>Você</span><strong class="score-gradient"><span class="reward-number count-pop">+800</span><span class="reward-unit"> BinCoins</span></strong></div>
            <div class="metric metric--class"><span>Turma</span><strong class="team-reward"><span class="reward-number">+1</span><span class="reward-unit"> ponto</span></strong></div>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-jump="sleep">Concluir</button>
        </div>
      </section>
    `,
  },
  {
    id: "teacher",
    label: "Professor",
    render: () => `
      <section class="screen screen--big screen--stack-action">
        ${topbar("Professor")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1nIdea, "Chame um professor para conferir comigo.", "big character-idea")}
          <div class="teacher-card">
            <strong>Compartimento travado</strong>
            <span>Não force a abertura. É só pedir ajuda.</span>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-jump="idle">Entendi</button>
        </div>
      </section>
    `,
  },
];

let currentIndex = 0;
let flowMode = "student";
let selectedSegment = null;
let selectedYear = null;
let selectedClass = null;
let selectedStudent = null;
let searchQuery = "";
let searchActive = false;
let keyboardShift = true;
let lastPressedKey = null;
let keyPulseTimer = null;
let keyboardOpening = false;
let keyboardClosing = false;
let keyboardCloseTimer = null;
let pinDigits = 0;
let pinWarning = false;
let historyStack = [];
let autoAdvanceTimer = null;

function applyReviewParams() {
  const params = new URLSearchParams(window.location.search);
  const screenParam = params.get("screen");

  if (!screenParam) {
    return;
  }

  flowMode = params.get("mode") ?? "student";
  selectedSegment = params.get("segment") ?? "fundamental2";
  selectedYear = params.get("year") ?? schoolTree[selectedSegment]?.years?.[0] ?? "7º Ano";
  selectedClass = params.get("class") ?? "A";
  selectedStudent = params.get("student") ?? "Marco C.";
  searchQuery = params.get("search") ?? "";
  searchActive = params.has("search") || params.get("searchActive") === "1";
  pinDigits = Number(params.get("pin") ?? (screenParam === "pin" ? 4 : 0));

  const screenIndex = screens.findIndex((screen) => screen.id === screenParam);
  if (screenIndex >= 0) {
    currentIndex = screenIndex;
  }
}

function topbar(step, options = {}) {
  const canGoBack = options.back !== false && currentIndex > 1 && screens[currentIndex]?.id !== "sleep";
  return `
    <div class="topbar">
      ${canGoBack ? `<button class="back-button" data-back aria-label="Voltar"><svg class="back-icon" aria-hidden="true" viewBox="0 0 24 24"><path d="M15 6L9 12L15 18" /><path d="M10 12H20" /></svg></button>` : `<span class="back-placeholder" aria-hidden="true"></span>`}
      <span class="step">${step}</span>
    </div>
  `;
}

function arrowIcon(direction = "right") {
  const points = direction === "left"
    ? '<path d="M15 6L9 12L15 18" /><path d="M10 12H20" />'
    : '<path d="M9 6L15 12L9 18" /><path d="M14 12H4" />';
  return `<svg class="nav-arrow nav-arrow--${direction}" aria-hidden="true" viewBox="0 0 24 24">${points}</svg>`;
}

function talk(asset, text, variant = "corner") {
  return `
    <div class="b1n-talk b1n-talk--${variant}">
      <div class="guide-bubble">${text}</div>
      <span class="b1n-avatar"><img src="${asset}" alt="B1N falando" /></span>
    </div>
  `;
}

function visualKeyboard() {
  return `
    <div class="visual-keyboard ${keyboardOpening ? "is-opening" : ""}" aria-label="Teclado visual">
      ${keyboardRows.map((row) => `
        <div class="keyboard-row" style="--key-count: ${row.length}">
          ${row.map((key) => `<button class="keyboard-key" data-key="${key}" data-label="${keyboardShift ? key.toUpperCase() : key}"><span>${keyboardShift ? key.toUpperCase() : key}</span></button>`).join("")}
        </div>
      `).join("")}
      <div class="keyboard-row keyboard-row--actions" style="--key-count: 3">
        <button class="keyboard-key keyboard-key--shift ${keyboardShift ? "active" : ""}" data-key="shift" data-label="Aa" aria-label="Maiúscula"><span>Aa</span></button>
        <button class="keyboard-key keyboard-key--wide" data-key="space" data-label="Espaço"><span>Espaço</span></button>
        <button class="keyboard-key keyboard-key--wide" data-key="backspace" data-label="Apagar"><span>Apagar</span></button>
      </div>
    </div>
  `;
}

function filteredStudents() {
  const query = normalize(searchQuery);
  return students
    .slice()
    .sort((a, b) => a.localeCompare(b, "pt-BR"))
    .filter((name) => !query || normalize(name).includes(query));
}

function normalize(value) {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

function resetState() {
  flowMode = "student";
  selectedSegment = null;
  selectedYear = null;
  selectedClass = null;
  selectedStudent = null;
  searchQuery = "";
  searchActive = false;
  keyboardShift = true;
  pinDigits = 0;
  pinWarning = false;
  historyStack = [];
}

function resetFlow() {
  resetState();
  currentIndex = 0;
  render();
}

function cancelDiscard() {
  resetState();
  currentIndex = screens.findIndex((screen) => screen.id === "idle");
  render();
}

function render() {
  const kiosk = document.querySelector("#kiosk");
  const screenList = document.querySelector("#screenList");
  clearTimeout(autoAdvanceTimer);

  kiosk.innerHTML = screens[currentIndex].render();
  keyboardOpening = false;
  if (screenList) {
    screenList.innerHTML = screens
      .map((screen, index) => `
        <button class="screen-chip ${index === currentIndex ? "active" : ""}" data-screen="${index}">
          ${String(index + 1).padStart(2, "0")} - ${screen.label}
        </button>
      `)
      .join("");
  }

  document.querySelectorAll("[data-mode]").forEach((button) => {
    button.addEventListener("click", () => {
      flowMode = button.dataset.mode;
    });
  });

  document.querySelectorAll("[data-segment]").forEach((button) => {
    button.addEventListener("click", () => {
      selectedSegment = button.dataset.segment;
      selectedYear = null;
      selectedClass = null;
    });
  });

  document.querySelectorAll("[data-year]").forEach((button) => {
    button.addEventListener("click", () => {
      selectedYear = button.dataset.year;
      selectedClass = null;
    });
  });

  document.querySelectorAll("[data-class]").forEach((button) => {
    button.addEventListener("click", () => {
      selectedClass = button.dataset.class;
      searchQuery = "";
      searchActive = false;
    });
  });

  document.querySelectorAll("[data-student]").forEach((button) => {
    button.addEventListener("click", () => {
      selectedStudent = button.dataset.student;
      searchQuery = selectedStudent;
      searchActive = false;
    });
  });

  document.querySelectorAll("[data-search-toggle]").forEach((box) => {
    box.addEventListener("click", (event) => {
      event.stopPropagation();
      clearTimeout(keyboardCloseTimer);
      keyboardOpening = !searchActive;
      keyboardClosing = false;
      searchActive = true;
      if (!searchQuery) {
        keyboardShift = true;
      }
      render();
    });
  });

  document.querySelectorAll("[data-search-screen]").forEach((screen) => {
    screen.addEventListener("click", (event) => {
      if (!searchActive) {
        return;
      }
      if (event.target.closest(".search-box, .visual-keyboard, [data-student], [data-next], [data-back]")) {
        return;
      }
      closeSearchKeyboard();
    });
  });

  document.querySelectorAll("[data-key]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      handleSearchKey(button.dataset.key);
    });
  });

  document.querySelectorAll("[data-pin]").forEach((button) => {
    button.addEventListener("click", () => handlePin(button.dataset.pin));
  });

  document.querySelectorAll("[data-next]:not([disabled])").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const target = button.dataset.next;
      target ? jump(target) : next();
    });
  });

  document.querySelectorAll("[data-jump]").forEach((button) => {
    button.addEventListener("click", () => jump(button.dataset.jump));
  });

  document.querySelectorAll("[data-cancel-discard]").forEach((button) => {
    button.addEventListener("click", cancelDiscard);
  });

  document.querySelectorAll("[data-back]").forEach((button) => {
    button.addEventListener("click", back);
  });

  document.querySelectorAll("[data-screen]").forEach((button) => {
    button.addEventListener("click", () => {
      currentIndex = Number(button.dataset.screen);
      render();
    });
  });

  document.querySelectorAll("img").forEach((image) => {
    image.setAttribute("draggable", "false");
  });

  const autoTarget = document.querySelector("[data-auto-next]")?.dataset.autoNext;
  if (autoTarget) {
    autoAdvanceTimer = setTimeout(() => jump(autoTarget), 3000);
  }
}

function next() {
  goToIndex(Math.min(currentIndex + 1, screens.length - 1));
}

function jump(id) {
  if (id === "sleep") {
    resetFlow();
    return;
  }

  if (id === "idle") {
    cancelDiscard();
    return;
  }

  const found = screens.findIndex((screen) => screen.id === id);
  if (found >= 0) {
    goToIndex(found);
  }
}

function goToIndex(index) {
  if (index === currentIndex) {
    return;
  }
  historyStack.push(currentIndex);
  currentIndex = index;
  render();
}

function back() {
  const previousIndex = historyStack.pop();
  if (previousIndex === undefined) {
    return;
  }
  currentIndex = previousIndex;
  pinWarning = false;
  render();
}

function handleSearchKey(key) {
  if (key === "clear") {
    searchQuery = "";
    searchActive = false;
    keyboardShift = true;
  } else if (key === "backspace") {
    searchQuery = searchQuery.slice(0, -1);
  } else if (key === "space") {
    searchQuery = `${searchQuery} `;
  } else if (key === "shift") {
    keyboardShift = !keyboardShift;
  } else {
    searchQuery = `${searchQuery}${keyboardShift ? key.toUpperCase() : key}`;
    keyboardShift = false;
  }
  render();
}

function handlePin(key) {
  pinWarning = false;
  if (key === "Apagar") {
    pinDigits = Math.max(0, pinDigits - 1);
  } else if (key === "OK") {
    if (pinDigits >= 4) {
      next();
      return;
    }
    pinWarning = true;
  } else {
    pinDigits = Math.min(4, pinDigits + 1);
  }
  render();
}

function visualKeyboard() {
  return `
    <div class="visual-keyboard" aria-label="Teclado visual">
      ${keyboardRows.map((row) => `
        <div class="keyboard-row" style="--key-count: ${row.length}">
          ${row.map((key) => `<button class="keyboard-key ${lastPressedKey === key ? "pressed" : ""}" data-key="${key}" data-label="${keyboardShift ? key.toUpperCase() : key}"><span>${keyboardShift ? key.toUpperCase() : key}</span></button>`).join("")}
        </div>
      `).join("")}
      <div class="keyboard-row keyboard-row--actions" style="--key-count: 3">
        <button class="keyboard-key keyboard-key--shift ${keyboardShift ? "active" : ""} ${lastPressedKey === "shift" ? "pressed" : ""}" data-key="shift" data-label="Aa" aria-label="Maiúscula"><span>Aa</span></button>
        <button class="keyboard-key keyboard-key--wide ${lastPressedKey === "space" ? "pressed" : ""}" data-key="space" data-label="Espaço"><span>Espaço</span></button>
        <button class="keyboard-key keyboard-key--wide ${lastPressedKey === "backspace" ? "pressed" : ""}" data-key="backspace" data-label="Apagar"><span>Apagar</span></button>
      </div>
    </div>
  `;
}

function resetState() {
  flowMode = "student";
  selectedSegment = null;
  selectedYear = null;
  selectedClass = null;
  selectedStudent = null;
  searchQuery = "";
  searchActive = false;
  keyboardShift = true;
  lastPressedKey = null;
  keyboardOpening = false;
  keyboardClosing = false;
  clearTimeout(keyboardCloseTimer);
  pinDigits = 0;
  pinWarning = false;
  historyStack = [];
}

function handleSearchKey(key) {
  lastPressedKey = key;
  clearTimeout(keyPulseTimer);

  if (key === "clear") {
    searchQuery = "";
    closeSearchKeyboard();
    return;
  } else if (key === "backspace") {
    searchQuery = searchQuery.slice(0, -1);
    keyboardShift = searchQuery.length === 0;
  } else if (key === "space") {
    searchQuery = `${searchQuery} `;
    keyboardShift = false;
  } else if (key === "shift") {
    keyboardShift = !keyboardShift;
  } else {
    searchQuery = `${searchQuery}${keyboardShift ? key.toUpperCase() : key}`;
    keyboardShift = searchQuery.length === 0;
  }

  render();

  keyPulseTimer = setTimeout(() => {
    lastPressedKey = null;
    if (screens[currentIndex]?.id === "student" && searchActive) {
      render();
    }
  }, 300);
}

function closeSearchKeyboard() {
  clearTimeout(keyboardCloseTimer);
  if (!searchActive && !keyboardClosing) {
    return;
  }

  searchActive = false;
  keyboardShift = true;
  keyboardOpening = false;
  keyboardClosing = true;
  render();

  keyboardCloseTimer = setTimeout(() => {
    keyboardClosing = false;
    if (screens[currentIndex]?.id === "student") {
      render();
    }
  }, 260);
}

document.querySelector("#nextBtn")?.addEventListener("click", next);
document.addEventListener("dragstart", (event) => {
  if (event.target instanceof HTMLImageElement) {
    event.preventDefault();
  }
});
applyReviewParams();
render();
