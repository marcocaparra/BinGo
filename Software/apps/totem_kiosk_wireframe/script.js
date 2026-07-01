const assets = {
  logo: "./assets/brand/logo_bingo_sem_slogan.png",
  b1n: "./assets/characters/b1n_joinha_confirmacao_web.png",
  b1nCorner: "./assets/characters/b1n_joinha_confirmacao_corner_norm_web.png",
  b1nDoubt: "./assets/characters/b1n_duvida_pergunta_web.png",
  b1nDoubtCorner: "./assets/characters/b1n_duvida_pergunta_corner_norm_web.png",
  b1nIdea: "./assets/characters/b1n_ideia_instrucao_web.png",
  b1nIdeaCorner: "./assets/characters/b1n_ideia_instrucao_corner_norm_web.png",
  b1nPrivacy: "./assets/characters/b1n_privacidade_pin_olhos_fechados_web.png",
  b1nPrivacyCorner: "./assets/characters/b1n_privacidade_pin_olhos_fechados_corner_norm_web.png",
  b1nSleep: "./assets/characters/b1n_dormindo_kiosk_idle_clean_web.png",
  b1nPointLeft: "./assets/characters/b1n_apontando_esquerda_compartimento_web.png",
  b1nAnalyze: "./assets/characters/b1n_lupa_analise_web.png",
  b1nReward: "./assets/characters/b1n_segurando_bincoin_recompensa_web.png",
};

const itemOptions = [
  {
    id: "battery",
    title: "Pilha ou bateria",
    subtitle: "Cuidado especial",
    image: "./assets/items/descarte_pilha_bateria_web.png",
    needsStrictSafety: true,
    next: "safety",
  },
  {
    id: "cable",
    title: "Cabo",
    subtitle: "Carregador/fio",
    image: "./assets/items/descarte_cabo_usb_web.png",
    needsStrictSafety: false,
    next: "safety",
  },
  {
    id: "phone",
    title: "Celular",
    subtitle: "Com professor",
    image: "./assets/items/descarte_celular_smartphone_web.png",
    needsStrictSafety: true,
    next: "teacher",
  },
  {
    id: "small",
    title: "Item pequeno",
    subtitle: "Mouse, fone...",
    image: "./assets/items/descarte_mouse_item_pequeno_web.png",
    needsStrictSafety: false,
    next: "safety",
  },
];

const classOptions = [
  "6º Ano A",
  "7º Ano A",
  "8º Ano A",
  "9º Ano A",
  "1ª Série A",
  "2ª Série A",
  "3ª Série A",
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
    label: "Registro",
    render: () => `
      <section class="screen screen--big screen--stack-action">
        ${topbar("Registro")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1n, "Como quer participar?", "big character-joinha")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-mode="student" data-next>Quero BinCoins</button>
          <button class="secondary-action" data-mode="classOnly" data-jump="class">Só pontuar pra turma</button>
        </div>
      </section>
    `,
  },
  {
    id: "class",
    label: "Turma",
    render: () => `
      <section class="screen screen--corner screen--no-action compact-screen">
        ${topbar("Turma")}
        <div class="content-zone content-zone--corner">
          ${talk(assets.b1nCorner, "Toque na sua turma.", "corner")}
          <div class="list class-list">
            ${classOptions.map((item) => `
              <button class="list-button" data-next="${flowMode === "classOnly" ? "insert" : "student"}"><span>${item}</span>${arrowIcon("right")}</button>
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
      <section class="screen screen--corner screen--no-action">
        ${topbar("Aluno")}
        <div class="content-zone content-zone--corner">
          ${talk(assets.b1nDoubtCorner, "Escolha seu nome.", "corner")}
          <div class="list">
            ${["Marco C.", "Gustavo B.", "Guilherme A.", "Alencar S."].map((item) => `
              <button class="list-button" data-next><span>${item}</span>${arrowIcon("right")}</button>
            `).join("")}
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "pin",
    label: "PIN",
    render: () => `
      <section class="screen screen--corner screen--no-action">
        ${topbar("PIN")}
        <div class="content-zone content-zone--corner">
          ${talk(assets.b1nPrivacyCorner, "Digite seu PIN. Eu não olho.", "corner privacy-guide")}
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
          <div class="insert-visual">
            <div class="slot-hint" aria-hidden="true">
              ${arrowIcon("left")}
              <span>Entrada à esquerda</span>
            </div>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-next="analyzing">Pronto, coloquei</button>
        </div>
      </section>
    `,
  },
  {
    id: "analyzing",
    label: "Análise",
    render: () => `
      <section class="screen screen--big">
        ${topbar("Analisando")}
        <div class="content-zone content-zone--big content-zone--analysis">
          ${talk(assets.b1nAnalyze, "Não retire ainda. Estou conferindo.", "big analysis-talk character-analyze")}
          <div class="progress"><span></span></div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-next>Ver pontos</button>
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
          ${talk(assets.b1nReward, "Boa! Descarte confirmado.", "big character-reward")}
          <div class="reward-card">
            <div class="metric metric--class"><span>Turma</span><strong class="score-gradient"><span class="reward-number">+20</span><span class="reward-unit"> pontos</span></strong></div>
            <div class="metric"><span>Você</span><strong class="score-gradient"><span class="reward-number">+8</span><span class="reward-unit"> BinCoins</span></strong></div>
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
      <section class="screen screen--big">
        ${topbar("Professor")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1nIdea, "Esse item precisa de um professor responsável antes de continuar.", "big character-idea")}
          <div class="teacher-card">
            <strong>Aguardando ajuda</strong>
            <span>O compartimento fica travado. Não force a abertura.</span>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-jump="sleep">Finalizar aviso</button>
        </div>
      </section>
    `,
  },
];

let currentIndex = 0;
let flowMode = "student";
let pinDigits = 0;
let pinWarning = false;
let selectedItem = null;
let historyStack = [];

function topbar(step) {
  const canGoBack = currentIndex > 1 && screens[currentIndex]?.id !== "sleep";
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

function choice(option) {
  const selected = selectedItem?.id === option.id;
  return `
    <button class="choice-card ${selected ? "selected" : ""}" data-item="${option.id}">
      <span class="choice-media"><img src="${option.image}" alt="" /></span>
      <strong>${option.title}</strong>
      <small>${option.subtitle}</small>
    </button>
  `;
}

function safetyContent() {
  if (selectedItem?.needsStrictSafety) {
    return {
      strict: true,
      speech: "Esse tipo precisa de atenção. Olha rapidinho comigo.",
      title: "Se tiver qualquer sinal estranho, chame um professor.",
      text: "Não coloque se estiver quente, estufado, quebrado ou vazando.",
      checks: [
        { icon: "FRIO", label: "Frio" },
        { icon: "OK", label: "Inteiro" },
        { icon: "SECO", label: "Sem vazamento" },
      ],
    };
  }

  return {
    strict: false,
    speech: "Confere se está inteiro antes de colocar.",
    title: "Tudo certo?",
    text: "Se tiver ponta quebrada, fio exposto ou cheiro estranho, chame um professor.",
    checks: [
      { icon: "OK", label: "Inteiro" },
      { icon: "FIO", label: "Sem fio exposto" },
      { icon: "OK", label: "Sem peça solta" },
    ],
  };
}

function render() {
  const kiosk = document.querySelector("#kiosk");
  const screenList = document.querySelector("#screenList");
  kiosk.innerHTML = screens[currentIndex].render();
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

  document.querySelectorAll("[data-pin]").forEach((button) => {
    button.addEventListener("click", () => handlePin(button.dataset.pin));
  });

  document.querySelectorAll("[data-item]").forEach((button) => {
    button.addEventListener("click", () => selectItem(button.dataset.item));
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
}

function next() {
  goToIndex(Math.min(currentIndex + 1, screens.length - 1));
}

function previous() {
  back();
}

function jump(id) {
  const found = screens.findIndex((screen) => screen.id === id);
  if (found >= 0) {
    if (id === "sleep") {
      flowMode = "student";
      pinDigits = 0;
      pinWarning = false;
      selectedItem = null;
      historyStack = [];
      currentIndex = found;
      render();
      return;
    }
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

function selectItem(id) {
  selectedItem = itemOptions.find((item) => item.id === id) ?? null;
  render();
}

document.querySelector("#nextBtn")?.addEventListener("click", next);
document.querySelector("#prevBtn")?.addEventListener("click", previous);
document.addEventListener("dragstart", (event) => {
  if (event.target instanceof HTMLImageElement) {
    event.preventDefault();
  }
});
render();
