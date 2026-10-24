const assets = {
  logo: "./assets/brand/logo_bingo_sem_slogan_clean.png",
  b1n: "./assets/characters/b1n_joinha_confirmacao_web_clean.png",
  b1nCorner: "./assets/characters/b1n_joinha_confirmacao_corner_norm_web_clean.png",
  b1nDoubtCorner: "./assets/characters/b1n_duvida_pergunta_corner_norm_web_clean.png",
  b1nIdea: "./assets/characters/b1n_ideia_instrucao_web_clean.png",
  b1nIdeaCorner: "./assets/characters/b1n_ideia_instrucao_corner_norm_web_clean.png",
  b1nPrivacyCorner: "./assets/characters/b1n_privacidade_pin_olhos_fechados_corner_norm_web_clean.png",
  b1nPrivacy: "./assets/characters/b1n_privacidade_pin_olhos_fechados_web.png",
  b1nSleep: "./assets/characters/b1n_dormindo_kiosk_idle_recorte.png",
  b1nPointLeft: "./assets/characters/b1n_apontando_esquerda_compartimento_web_clean.png",
  b1nAnalyze: "./assets/characters/b1n_lupa_analise_web_clean.png",
  b1nReward: "./assets/characters/b1n_segurando_bincoin_recompensa_web_clean.png",
  detectedCable: "./assets/items/descarte_cabo_usb_web.png",
};

const itemOptions = [
  {
    id: "battery",
    title: "Pilha ou bateria",
    subtitle: "Cuidado especial",
    image: "./assets/items/descarte_pilha_bateria_web.png",
    cutout: "./assets/items/descarte_pilha_bateria_cutout_clean.png",
  },
  {
    id: "cable",
    title: "Cabo",
    subtitle: "Carregador/fio",
    image: "./assets/items/descarte_cabo_usb_web.png",
    cutout: "./assets/items/descarte_cabo_usb_cutout_clean.png",
  },
  {
    id: "phone",
    title: "Celular",
    subtitle: "Atenção especial",
    image: "./assets/items/descarte_celular_smartphone_web.png",
    cutout: "./assets/items/descarte_celular_smartphone_cutout_clean.png",
  },
  {
    id: "small",
    title: "Item pequeno",
    subtitle: "Mouse, fone...",
    image: "./assets/items/descarte_mouse_item_pequeno_web.png",
    cutout: "./assets/items/descarte_mouse_item_pequeno_cutout_clean.png",
  },
  {
    id: "unknown",
    title: "Eletrônico não identificado",
    subtitle: "Categoria geral",
    image: null,
    cutout: null,
  },
];

const schoolTree = {
  fundamental1: {
    label: "Fundamental I",
    speech: "Agora escolha o seu ano.",
    years: ["1º Ano", "2º Ano", "3º Ano", "4º Ano", "5º Ano"],
  },
  fundamental2: {
    label: "Fundamental II",
    speech: "Agora escolha o seu ano.",
    years: ["6º Ano", "7º Ano", "8º Ano", "9º Ano"],
  },
  medio: {
    label: "Ensino Médio",
    speech: "Agora escolha a sua série.",
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
        <img class="sleep-logo" src="${assets.logo}" alt="BinGo" data-demo-trigger />
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
          ${talk(assets.b1n, "Trouxe um eletrônico sem uso? Eu te guio.", "big welcome-talk character-joinha")}
        </div>
        <div class="action-zone action-zone--stack action-zone--single">
          <button class="primary-action wake-action" data-start-session>Iniciar descarte</button>
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
          ${talk(assets.b1n, "Como você quer participar?", "big character-joinha")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-mode="student" data-next>Participar com meu perfil</button>
          <button class="secondary-action class-only-action" data-mode="classOnly" data-next>Contribuir só com a turma</button>
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
          ${talk(assets.b1nCorner, "Escolha sua etapa escolar.", "corner")}
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
              <button class="list-button" data-class="${letter}" data-next="${flowMode === "classOnly" ? "safety" : ""}">
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
          ${talk(assets.b1nPrivacyCorner, "Digite seu PIN. Eu fecho os olhos.", "corner privacy-guide character-privacy")}
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
    id: "safety",
    label: "Segurança",
    render: () => `
      <section class="screen screen--corner screen--safety screen--stack-action">
        ${topbar("Segurança")}
        <div class="content-zone content-zone--corner content-zone--safety">
          ${talk(assets.b1nIdeaCorner, "Antes de abrir, vamos conferir o item.", "corner safety-guide")}
          <div class="safety-card">
            <strong>O item está seguro?</strong>
            <div class="safety-row"><span>1</span><p>Não está vazando nem estufado.</p></div>
            <div class="safety-row"><span>2</span><p>Não tem líquido nem parte cortante.</p></div>
            <p class="safety-note">Se notar algum risco, não coloque o item.</p>
          </div>
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-safety-safe>Sim, está seguro</button>
          <button class="alert-action" data-safety-risk>Encontrei um risco</button>
        </div>
      </section>
    `,
  },
  {
    id: "opening",
    label: "Abrindo porta",
    render: () => `
      <section class="screen screen--corner screen--process screen--door-process screen--auto" data-process="opening">
        ${topbar("Abertura", { back: false })}
        <div class="content-zone content-zone--computing">
          ${talk(assets.b1nIdeaCorner, "Vou abrir o compartimento para você.", "corner character-idea")}
          ${processSignal(doorIcon(), "Abrindo com segurança", "Aguarde a confirmação da porta.", "Hardware simulado")}
        </div>
      </section>
    `,
  },
  {
    id: "insert",
    label: "Inserir",
    render: () => `
      <section class="screen screen--big screen--insert">
        ${topbar("Abertura", { back: false })}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1nPointLeft, "Coloque somente um item na abertura.", "big insert-talk character-point-left")}
          <div class="single-item-note"><strong>1 item por vez</strong><span>Cada ciclo registra um único descarte.</span></div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-item-inserted>Coloquei um item</button>
        </div>
      </section>
    `,
  },
  {
    id: "hand-confirm",
    label: "Retirar mão",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--hand-confirm">
        ${topbar("Segurança", { back: false })}
        <div class="content-zone content-zone--corner content-zone--hand">
          ${talk(assets.b1nIdeaCorner, "Retire a mão antes de continuar.", "corner character-idea")}
          <div class="hand-signal" aria-hidden="true"><span class="material-hand">back_hand</span></div>
          <div class="instruction-note"><strong>Confira a abertura</strong><span>A porta só fecha depois da sua confirmação.</span></div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-hand-confirmed>Retirei a mão</button>
        </div>
      </section>
    `,
  },
  {
    id: "door-progress",
    label: "Fechando porta",
    render: () => `
      <section class="screen screen--corner screen--process screen--door-process screen--auto" data-process="closing">
        ${topbar("Preparando", { back: false })}
        <div class="content-zone content-zone--computing">
          ${talk(assets.b1nIdeaCorner, "Agora vou preparar a câmera.", "corner character-idea")}
          ${processSignal(doorIcon(), "Fechando a porta", "A câmera começa somente depois da confirmação.", "Hardware simulado")}
        </div>
      </section>
    `,
  },
  {
    id: "camera",
    label: "Câmera",
    render: () => `
      <section class="screen screen--camera screen--auto" data-auto-next="classification" data-auto-delay="2800">
        ${topbar("Câmera", { back: false })}
        <div class="content-zone content-zone--camera">
          ${talk(assets.b1nAnalyze, "Vou conferir o item por dentro.", "big camera-talk character-analyze")}
          <div class="camera-preview" aria-label="Preview da câmera interna">
            <div class="camera-bar"><span>Câmera interna</span><strong>AO VIVO</strong></div>
            <div class="camera-frame">
              <div class="scan-line"></div>
              <span class="camera-label">Item sendo identificado...</span>
            </div>
          </div>
          <span class="simulation-badge">Câmera simulada</span>
        </div>
      </section>
    `,
  },
  {
    id: "classification",
    label: "Classificação",
    render: () => `
      <section class="screen screen--big screen--analysis screen--auto" data-process="classification">
        ${topbar("Análise", { back: false })}
        <div class="content-zone content-zone--big content-zone--analysis">
          ${talk(assets.b1nAnalyze, "Estou identificando o eletrônico.", "big character-analyze")}
          <div class="analysis-progress"><span></span></div>
          <span class="simulation-badge">Classificador simulado</span>
        </div>
      </section>
    `,
  },
  {
    id: "secondary-analysis",
    label: "Análise complementar",
    render: () => `
      <section class="screen screen--big screen--analysis screen--auto" data-process="secondary">
        ${topbar("Nova análise", { back: false })}
        <div class="content-zone content-zone--big content-zone--analysis">
          ${talk(assets.b1nAnalyze, "Preciso conferir mais um detalhe.", "big character-analyze")}
          <div class="analysis-progress analysis-progress--secondary"><span></span></div>
          <span class="simulation-badge">Gemini simulado</span>
        </div>
      </section>
    `,
  },
  {
    id: "recognized",
    label: "Item reconhecido",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--item-focus screen--recognized">
        ${topbar("Reconhecimento")}
        <div class="content-zone content-zone--item-focus">
          ${talk(assets.b1nCorner, "Encontrei este item. Confira comigo.", "corner")}
          ${itemSummary("Item reconhecido")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-recognition-confirm>Sim, está certo</button>
          <button class="secondary-action correction-action" data-correction-open>Corrigir</button>
        </div>
      </section>
    `,
  },
  {
    id: "correct-item",
    label: "Corrigir item",
    render: () => `
      <section class="screen screen--corner screen--correct-item">
        ${topbar("Corrigir item")}
        <div class="content-zone content-zone--compact-list">
          ${talk(assets.b1nIdeaCorner, "Qual item aparece na imagem?", "corner character-idea")}
          <div class="correction-item-list">
            ${correctionCandidates().map((item) => `
              <button class="correction-item ${draftRecognizedItem.id === item.id ? "selected" : ""}" data-correct-item="${item.id}">
                ${itemMedia(item, "correction-item-media")}
                <span><strong>${item.title}</strong><small>${item.subtitle}</small></span>
                <span class="selection-mark" aria-hidden="true"></span>
              </button>
            `).join("")}
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-apply-correction>Confirmar correção</button>
        </div>
      </section>
    `,
  },
  {
    id: "review",
    label: "Revisão final",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--item-focus screen--review">
        ${topbar("Revisão final")}
        <div class="content-zone content-zone--item-focus">
          ${talk(assets.b1nCorner, "Confira o item antes de confirmar o descarte.", "corner")}
          ${itemSummary("Seu descarte")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-discard-confirm>Confirmar descarte</button>
          <button class="secondary-action correction-action" data-correction-open>Corrigir</button>
        </div>
      </section>
    `,
  },
  {
    id: "computing",
    label: "Registrando descarte",
    render: () => `
      <section class="screen screen--corner screen--auto screen--computing" data-process="computing">
        ${topbar("Descarte", { back: false })}
        <div class="content-zone content-zone--computing">
          ${talk(assets.b1nIdeaCorner, "Vou concluir o ciclo e preparar o registro.", "corner character-idea")}
          <div class="computing-signal">
            <span class="computing-icon">${recordIcon()}</span>
            <strong>Só mais um instante</strong>
            <small>Executando o ciclo mecânico e preparando o registro.</small>
            <span class="simulation-badge">Hardware e registro simulados</span>
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "post-drop-recovery",
    label: "Registro pendente",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--critical">
        ${topbar("Conexão", { back: false })}
        <div class="content-zone content-zone--corner content-zone--critical">
          ${talk(assets.b1nIdeaCorner, "O item foi recebido e está protegido.", "corner character-idea")}
          ${statusPanel("Registro preservado", "A conexão caiu depois do ciclo físico. Nenhum novo descarte é necessário.", "Conexão simulada")}
        </div>
        <div class="action-zone">
          <button class="primary-action" data-restore-connection>Restabelecer conexão</button>
        </div>
      </section>
    `,
  },
  {
    id: "success",
    label: "Descarte validado",
    render: () => `
      <section class="screen screen--big screen--success screen--success--${flowMode} screen--auto" data-auto-next="sleep" data-auto-delay="6000">
        ${topbar("Concluído", { back: false })}
        <div class="content-zone content-zone--success">
          ${talk(assets.b1nReward, "Boa escolha! Descarte validado.", "big character-reward success-talk")}
          <div class="reward-list">
            <div class="metric metric--class"><span>Pontos da turma</span><strong class="score-gradient"><span class="reward-number">+19</span><span class="reward-unit"> pts</span></strong></div>
            ${flowMode === "student" ? `<div class="metric metric--student"><span>Seus BinCoins</span><strong class="score-gradient"><span class="reward-number">+8</span><span class="reward-unit"> BinCoins</span></strong></div>` : ""}
            <span class="simulation-badge">Registro simulado</span>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-jump="sleep">Concluir</button>
        </div>
      </section>
    `,
  },
  {
    id: "unavailable",
    label: "Fora de operação",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--critical">
        ${topbar("Indisponível", { back: false })}
        <div class="content-zone content-zone--corner content-zone--critical">
          ${talk(assets.b1nIdeaCorner, "Não consigo iniciar um descarte agora.", "corner character-idea")}
          ${statusPanel("Totem fora de operação", "Os serviços necessários estão indisponíveis. Tente novamente mais tarde.", "Verificação simulada")}
        </div>
        <div class="action-zone"><button class="primary-action" data-jump="sleep">Entendi</button></div>
      </section>
    `,
  },
  {
    id: "rejected",
    label: "Item recusado",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--critical">
        ${topbar("Item não aceito", { back: false })}
        <div class="content-zone content-zone--corner content-zone--critical">
          ${talk(assets.b1nDoubtCorner, "Não consegui confirmar este eletrônico.", "corner character-doubt")}
          ${statusPanel("Vamos devolver o item", "Nenhum descarte será registrado e nenhum resultado será gerado.", "IA simulada")}
        </div>
        <div class="action-zone"><button class="primary-action" data-return-start>Abrir para retirar</button></div>
      </section>
    `,
  },
  {
    id: "return-progress",
    label: "Devolvendo item",
    render: () => `
      <section class="screen screen--corner screen--process screen--auto" data-auto-next="return-confirm" data-auto-delay="2200">
        ${topbar("Devolução", { back: false })}
        <div class="content-zone content-zone--computing">
          ${talk(assets.b1nIdeaCorner, "Vou abrir para você retirar o item.", "corner character-idea")}
          ${processSignal(doorIcon(), "Preparando a retirada", "Aguarde a abertura completa.", "Hardware simulado")}
        </div>
      </section>
    `,
  },
  {
    id: "connection-interrupted",
    label: "Conexão interrompida",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--critical">
        ${topbar("Conexão", { back: false })}
        <div class="content-zone content-zone--corner content-zone--critical">
          ${talk(assets.b1nIdeaCorner, "A conexão caiu antes do descarte.", "corner character-idea")}
          ${statusPanel("O item não foi liberado", "Vamos devolver o eletrônico com segurança. Nenhum resultado foi gerado.", "Conexão simulada")}
        </div>
        <div class="action-zone"><button class="primary-action" data-return-start>Devolver item</button></div>
      </section>
    `,
  },
  {
    id: "return-confirm",
    label: "Retirar item",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--critical">
        ${topbar("Retirada", { back: false })}
        <div class="content-zone content-zone--corner content-zone--critical">
          ${talk(assets.b1nIdeaCorner, "Retire o item da abertura.", "corner character-idea")}
          ${statusPanel("Compartimento aberto", "Confira se a abertura ficou livre antes de encerrar.", "Hardware simulado")}
        </div>
        <div class="action-zone"><button class="primary-action" data-return-confirm>Retirei o item</button></div>
      </section>
    `,
  },
  {
    id: "mechanical-error",
    label: "Falha mecânica",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--critical">
        ${topbar("Atenção", { back: false })}
        <div class="content-zone content-zone--corner content-zone--critical">
          ${talk(assets.b1nIdeaCorner, "O equipamento precisa de ajuda.", "corner character-idea")}
          ${statusPanel("Movimento não confirmado", "Não toque na abertura. O Totem ficará bloqueado.", "Falha simulada")}
        </div>
        <div class="action-zone"><button class="alert-action" data-jump="teacher">Chamar responsável</button></div>
      </section>
    `,
  },
  {
    id: "teacher",
    label: "Professor",
    render: () => `
      <section class="screen screen--big screen--stack-action">
        ${topbar("Professor", { back: false })}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1nIdea, "Procure um responsável antes de continuar.", "big character-idea")}
          <div class="teacher-card">
            <strong>Nenhum descarte foi registrado</strong>
            <span>Não force a abertura nem toque no item.</span>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-jump="sleep">Entendi</button>
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
let recognizedItem = itemOptions.find((item) => item.id === "cable");
let draftRecognizedItem = recognizedItem;
let visionItem = recognizedItem;
let visionCandidateIds = ["cable", "small", "phone"];
let classificationOrigin = "VISION_PRIMARY";
let demoScenario = "success";
let demoPanelOpen = false;
let demoPressTimer = null;
let safetyConfirmed = false;
let handConfirmed = false;
let doorStatus = "closed";
let classificationStatus = "idle";
let recognitionOutcome = null;
let reviewConfirmed = false;
let mechanismStatus = "idle";
let registrationStatus = "idle";

function applyReviewParams() {
  const params = new URLSearchParams(window.location.search);
  const screenParam = params.get("screen");
  demoScenario = params.get("scenario") ?? "success";
  demoPanelOpen = params.get("demo") === "1";

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
  safetyConfirmed = true;
  handConfirmed = true;
  doorStatus = "closed";
  classificationStatus = "complete";
  recognitionOutcome = "electronic";
  reviewConfirmed = true;
  mechanismStatus = "complete";
  registrationStatus = screenParam === "success" ? "complete" : "idle";

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
      <img class="logo" src="${assets.logo}" alt="BinGo" data-demo-trigger />
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

function controlIcon(paths) {
  return `<svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">${paths}</svg>`;
}

function editIcon() {
  return controlIcon('<path d="M4 20H8L19 9L15 5L4 16V20Z" /><path d="M13.5 6.5L17.5 10.5" />');
}

function recordIcon() {
  return controlIcon('<path d="M6 4H18V20H6Z" /><path d="M9 8H15M9 12H15M9 16H13" />');
}

function doorIcon() {
  return controlIcon('<path d="M6 3H18V21H6Z" /><path d="M9 6H15V18H9Z" /><path d="M13.5 12H14" />');
}

function talk(asset, text, variant = "corner") {
  return `
    <div class="b1n-talk b1n-talk--${variant}">
      <div class="guide-bubble">${text}</div>
      <span class="b1n-avatar"><img src="${asset}" alt="B1N falando" /></span>
    </div>
  `;
}

function itemSummary(label) {
  return `
    <div class="item-focus">
      <span class="item-focus-label">${label}</span>
      ${itemMedia(recognizedItem, "item-focus-media")}
      <div class="item-focus-footer">
        <strong>${recognizedItem.title}</strong>
        <span class="single-item-pill">1 item</span>
      </div>
    </div>
  `;
}

function itemMedia(item, className) {
  if (!item?.cutout) {
    return `<span class="${className} item-media--unknown"><b>?</b></span>`;
  }
  return `<span class="${className}"><img src="${item.cutout}" alt="" /></span>`;
}

function processSignal(icon, title, description, badge) {
  return `
    <div class="computing-signal process-signal">
      <span class="computing-icon">${icon}</span>
      <strong>${title}</strong>
      <small>${description}</small>
      <span class="simulation-badge">${badge}</span>
    </div>
  `;
}

function statusPanel(title, description, badge) {
  return `
    <div class="status-panel">
      <span class="status-mark" aria-hidden="true">!</span>
      <strong>${title}</strong>
      <span>${description}</span>
      <small>${badge}</small>
    </div>
  `;
}

function correctionCandidates() {
  const candidates = visionCandidateIds
    .map((id) => itemOptions.find((item) => item.id === id))
    .filter(Boolean);
  const unknown = itemOptions.find((item) => item.id === "unknown");
  return recognitionOutcome === "electronic" && unknown ? [...candidates, unknown] : candidates;
}

function scenarioPanel() {
  if (!demoPanelOpen) {
    return "";
  }
  const scenarios = [
    ["success", "Sucesso direto"],
    ["uncertain", "Incerteza resolvida"],
    ["rejected", "Item recusado"],
    ["risk", "Item com risco"],
    ["unavailable", "Totem indisponível"],
    ["mechanical", "Falha mecânica"],
    ["connection-before", "Conexão antes da queda"],
    ["connection-after", "Conexão depois da queda"],
  ];
  return `
    <div class="demo-panel" role="dialog" aria-label="Cenários de demonstração">
      <div class="demo-panel-head"><strong>Cenário da demo</strong><button data-demo-close aria-label="Fechar">×</button></div>
      <div class="demo-scenarios">
        ${scenarios.map(([id, label]) => `<button class="${demoScenario === id ? "selected" : ""}" data-demo-scenario="${id}"><span>${label}</span><b></b></button>`).join("")}
      </div>
      <small>Todos os resultados são simulados.</small>
    </div>
  `;
}

function openReview() {
  jump("review");
}

function openCorrection() {
  draftRecognizedItem = recognizedItem;
  jump("correct-item");
}

function correctRecognizedItem(itemId) {
  draftRecognizedItem = itemOptions.find((item) => item.id === itemId) ?? draftRecognizedItem;
  render();
}

function applyCorrection() {
  recognizedItem = draftRecognizedItem;
  classificationOrigin = recognizedItem.id === "unknown" ? "UNIDENTIFIED" : "USER_CORRECTED";
  discardCorrectionDraft();
  jump("review");
}

function discardCorrectionDraft() {
  draftRecognizedItem = recognizedItem;
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

const kiosk = document.querySelector("#kiosk");
const preloadedAssets = new Set();

function studentListMarkup() {
  return filteredStudents().map((name) => `
    <button class="list-button student-button" data-student="${name}" data-next>
      <span>${name}</span>${arrowIcon("right")}
    </button>
  `).join("") || `<div class="empty-state">Não achei esse nome. Tente apagar uma letra.</div>`;
}

function updateStudentSearch() {
  const screen = kiosk.querySelector("[data-search-screen]");
  if (!screen) {
    return;
  }

  const searchBox = screen.querySelector("[data-search-toggle]");
  const searchLabel = searchBox?.querySelector(":scope > span");
  const studentList = screen.querySelector(".student-list");
  screen.classList.toggle("is-searching", searchActive || keyboardClosing);
  searchBox?.classList.toggle("active", searchActive);
  searchBox?.classList.toggle("has-value", Boolean(searchQuery));
  if (searchLabel) {
    searchLabel.textContent = searchQuery || "Digite seu nome...";
    searchLabel.classList.toggle("search-placeholder", !searchQuery);
  }
  if (studentList) {
    studentList.innerHTML = studentListMarkup();
  }

  screen.querySelectorAll("[data-key]").forEach((keyButton) => {
    const key = keyButton.dataset.key;
    const label = keyboardRows.flat().includes(key) && keyboardShift
      ? key.toUpperCase()
      : keyButton.dataset.label;
    keyButton.classList.toggle("pressed", lastPressedKey === key);
    keyButton.classList.toggle("active", key === "shift" && keyboardShift);
    const text = keyButton.querySelector("span");
    if (text && keyboardRows.flat().includes(key)) {
      text.textContent = label;
      keyButton.dataset.label = label;
    }
  });
}

function updatePinView() {
  kiosk.querySelectorAll(".pin-dot").forEach((dot, index) => {
    dot.classList.toggle("filled", index < pinDigits);
  });
  const okButton = kiosk.querySelector('[data-pin="OK"]');
  if (okButton) {
    okButton.disabled = pinDigits < 4;
    okButton.classList.toggle("key-disabled", pinDigits < 4);
  }
  kiosk.querySelector(".pin-hint")?.classList.toggle("show", pinWarning);
}

function preloadNextScreenAssets() {
  const nextScreen = screens[Math.min(currentIndex + 1, screens.length - 1)];
  if (!nextScreen) {
    return;
  }
  const sources = [...nextScreen.render().matchAll(/src="([^"]+)"/g)].map((match) => match[1]);
  sources.forEach((source) => {
    if (preloadedAssets.has(source)) {
      return;
    }
    preloadedAssets.add(source);
    const image = new Image();
    image.decoding = "async";
    image.src = source;
  });
}

function scheduleAdjacentPreload() {
  if ("requestIdleCallback" in window) {
    window.requestIdleCallback(preloadNextScreenAssets, { timeout: 800 });
    return;
  }
  window.setTimeout(preloadNextScreenAssets, 120);
}

function render() {
  const screenList = document.querySelector("#screenList");
  clearTimeout(autoAdvanceTimer);

  kiosk.innerHTML = screens[currentIndex].render() + scenarioPanel();
  keyboardOpening = false;
  kiosk.querySelectorAll("img").forEach((image) => {
    image.decoding = "async";
    image.draggable = false;
  });
  scheduleAdjacentPreload();
  if (screenList) {
    screenList.innerHTML = screens
      .map((screen, index) => `
        <button class="screen-chip ${index === currentIndex ? "active" : ""}" data-screen="${index}">
          ${String(index + 1).padStart(2, "0")} - ${screen.label}
        </button>
      `)
      .join("");
  }

  const autoTarget = document.querySelector("[data-auto-next]")?.dataset.autoNext;
  if (autoTarget) {
    const autoDelay = Number(document.querySelector("[data-auto-delay]")?.dataset.autoDelay ?? 3000);
    autoAdvanceTimer = setTimeout(() => jump(autoTarget), autoDelay);
  }

  const process = document.querySelector("[data-process]")?.dataset.process;
  if (process === "opening") {
    autoAdvanceTimer = setTimeout(() => {
      if (demoScenario === "mechanical") {
        jump("mechanical-error");
        return;
      }
      doorStatus = "open";
      jump("insert");
    }, 2200);
  } else if (process === "closing") {
    autoAdvanceTimer = setTimeout(() => {
      doorStatus = "closed";
      jump("camera");
    }, 3200);
  } else if (process === "classification") {
    autoAdvanceTimer = setTimeout(resolveClassification, 2400);
  } else if (process === "secondary") {
    autoAdvanceTimer = setTimeout(resolveSecondaryClassification, 2600);
  } else if (process === "computing") {
    autoAdvanceTimer = setTimeout(completeProcessing, 4500);
  }
}

function handleKioskClick(event) {
  const target = event.target.closest("button, [data-search-toggle]");
  if (!target || !kiosk.contains(target)) {
    const searchScreen = event.target.closest("[data-search-screen]");
    if (searchScreen && searchActive) {
      closeSearchKeyboard();
    }
    return;
  }

  if (target.matches("[data-key]")) {
    event.stopPropagation();
    handleSearchKey(target.dataset.key);
    return;
  }
  if (target.matches("[data-pin]")) {
    handlePin(target.dataset.pin);
    return;
  }
  if (target.matches("[data-search-toggle]")) {
    event.stopPropagation();
    clearTimeout(keyboardCloseTimer);
    keyboardOpening = !searchActive;
    keyboardClosing = false;
    searchActive = true;
    if (!searchQuery) {
      keyboardShift = true;
    }
    render();
    return;
  }

  if (target.dataset.mode) {
    flowMode = target.dataset.mode;
  }
  if (target.dataset.segment) {
    selectedSegment = target.dataset.segment;
    selectedYear = null;
    selectedClass = null;
  }
  if (target.dataset.year) {
    selectedYear = target.dataset.year;
    selectedClass = null;
  }
  if (target.dataset.class) {
    selectedClass = target.dataset.class;
    searchQuery = "";
    searchActive = false;
  }
  if (target.dataset.student) {
    selectedStudent = target.dataset.student;
    searchQuery = selectedStudent;
    searchActive = false;
  }

  if (target.matches("[data-start-session]")) {
    demoScenario === "unavailable" ? jump("unavailable") : next();
    return;
  }
  if (target.matches("[data-safety-safe]")) {
    startOpening();
    return;
  }
  if (target.matches("[data-safety-risk]")) {
    jump("teacher");
    return;
  }
  if (target.matches("[data-item-inserted]")) {
    jump("hand-confirm");
    return;
  }
  if (target.matches("[data-hand-confirmed]")) {
    startDoorClose();
    return;
  }
  if (target.matches("[data-recognition-confirm]")) {
    openReview();
    return;
  }
  if (target.matches("[data-correction-open]")) {
    openCorrection();
    return;
  }
  if (target.dataset.correctItem) {
    correctRecognizedItem(target.dataset.correctItem);
    return;
  }
  if (target.matches("[data-apply-correction]")) {
    applyCorrection();
    return;
  }
  if (target.matches("[data-discard-confirm]")) {
    confirmDiscard();
    return;
  }
  if (target.matches("[data-return-start]")) {
    startReturn();
    return;
  }
  if (target.matches("[data-return-confirm]")) {
    resetFlow();
    return;
  }
  if (target.matches("[data-restore-connection]")) {
    registrationStatus = "complete";
    jump("success");
    return;
  }
  if (target.matches("[data-jump]")) {
    jump(target.dataset.jump);
    return;
  }
  if (target.matches("[data-cancel-discard]")) {
    cancelDiscard();
    return;
  }
  if (target.matches("[data-back]")) {
    back();
    return;
  }
  if (target.dataset.demoScenario) {
    demoScenario = target.dataset.demoScenario;
    demoPanelOpen = false;
    resetFlow();
    return;
  }
  if (target.matches("[data-demo-close]")) {
    demoPanelOpen = false;
    render();
    return;
  }
  if (target.dataset.screen) {
    currentIndex = Number(target.dataset.screen);
    render();
    return;
  }
  if (target.matches("[data-next]") && !target.disabled) {
    event.stopPropagation();
    const destination = target.dataset.next;
    destination ? jump(destination) : next();
    return;
  }

  const searchScreen = event.target.closest("[data-search-screen]");
  if (
    searchScreen
    && searchActive
    && !event.target.closest(".search-box, .visual-keyboard, [data-student], [data-back]")
  ) {
    closeSearchKeyboard();
  }
}

function handleDemoPointerDown(event) {
  if (!event.target.closest("[data-demo-trigger]")) {
    return;
  }
  clearTimeout(demoPressTimer);
  demoPressTimer = setTimeout(() => {
    demoPanelOpen = true;
    render();
  }, 2000);
}

function cancelDemoPress() {
  clearTimeout(demoPressTimer);
}

function startOpening() {
  safetyConfirmed = true;
  doorStatus = "opening";
  jump("opening");
}

function startDoorClose() {
  handConfirmed = true;
  doorStatus = "closing";
  jump("door-progress");
}

function resolveClassification() {
  classificationStatus = "complete";
  if (demoScenario === "rejected") {
    recognitionOutcome = "not-electronic";
    jump("rejected");
    return;
  }
  if (demoScenario === "uncertain") {
    classificationStatus = "secondary";
    jump("secondary-analysis");
    return;
  }
  recognitionOutcome = "electronic";
  recognizedItem = visionItem;
  classificationOrigin = "VISION_PRIMARY";
  jump("recognized");
}

function resolveSecondaryClassification() {
  classificationStatus = "complete";
  recognitionOutcome = "electronic";
  visionCandidateIds = ["cable", "battery", "small"];
  recognizedItem = visionItem;
  classificationOrigin = "VISION_SECONDARY";
  jump("recognized");
}

function confirmDiscard() {
  reviewConfirmed = true;
  if (demoScenario === "connection-before") {
    registrationStatus = "cancelled";
    jump("connection-interrupted");
    return;
  }
  mechanismStatus = "processing";
  registrationStatus = "processing";
  jump("computing");
}

function completeProcessing() {
  mechanismStatus = "complete";
  if (demoScenario === "connection-after") {
    registrationStatus = "pending";
    jump("post-drop-recovery");
    return;
  }
  registrationStatus = "complete";
  jump("success");
}

function startReturn() {
  doorStatus = "opening";
  jump("return-progress");
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

  const blocked = (
    (id === "opening" && !safetyConfirmed)
    || (id === "insert" && doorStatus !== "open")
    || (id === "hand-confirm" && doorStatus !== "open")
    || (id === "door-progress" && !handConfirmed)
    || (["camera", "classification"].includes(id) && doorStatus !== "closed")
    || (["recognized", "review"].includes(id) && recognitionOutcome !== "electronic")
    || (id === "computing" && !reviewConfirmed)
    || (id === "success" && registrationStatus !== "complete")
  );
  if (blocked) {
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
  if (screens[currentIndex]?.id === "correct-item") {
    discardCorrectionDraft();
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
  updatePinView();
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
  recognizedItem = itemOptions.find((item) => item.id === "cable");
  draftRecognizedItem = recognizedItem;
  visionItem = recognizedItem;
  visionCandidateIds = ["cable", "small", "phone"];
  classificationOrigin = "VISION_PRIMARY";
  safetyConfirmed = false;
  handConfirmed = false;
  doorStatus = "closed";
  classificationStatus = "idle";
  recognitionOutcome = null;
  reviewConfirmed = false;
  mechanismStatus = "idle";
  registrationStatus = "idle";
  demoPanelOpen = false;
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

  updateStudentSearch();

  keyPulseTimer = setTimeout(() => {
    lastPressedKey = null;
    if (screens[currentIndex]?.id === "student" && searchActive) {
      updateStudentSearch();
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

if (new URLSearchParams(window.location.search).get("runtime") === "demo") {
  const notice = document.createElement("div");
  notice.className = "demo-notice";
  notice.textContent = "Modo demonstração ativo. Os dados exibidos são simulados e não alteram o saldo real.";
  document.body.append(notice);
  kiosk.addEventListener("click", handleKioskClick);
  kiosk.addEventListener("pointerdown", handleDemoPointerDown);
  kiosk.addEventListener("pointerup", cancelDemoPress);
  kiosk.addEventListener("pointerleave", cancelDemoPress);
  kiosk.addEventListener("pointercancel", cancelDemoPress);
  applyReviewParams();
  render();
} else {
  // Parâmetros de revisão e timers do protótipo não participam do modo operacional.
  window.BinGoOperational.start(kiosk, { assets, talk, topbar, keyboardRows, normalize });
}
document.addEventListener("dragstart", (event) => {
  if (event.target instanceof HTMLImageElement) {
    event.preventDefault();
  }
});
