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
    cutout: "./assets/items/descarte_pilha_bateria_cutout.png",
    needsStrictSafety: true,
    next: "safety",
  },
  {
    id: "cable",
    title: "Cabo",
    subtitle: "Carregador/fio",
    image: "./assets/items/descarte_cabo_usb_web.png",
    cutout: "./assets/items/descarte_cabo_usb_cutout.png",
    needsStrictSafety: false,
    next: "safety",
  },
  {
    id: "phone",
    title: "Celular",
    subtitle: "Atenção especial",
    image: "./assets/items/descarte_celular_smartphone_web.png",
    cutout: "./assets/items/descarte_celular_smartphone_cutout.png",
    needsStrictSafety: true,
    next: "safety",
  },
  {
    id: "small",
    title: "Item pequeno",
    subtitle: "Mouse, fone...",
    image: "./assets/items/descarte_mouse_item_pequeno_web.png",
    cutout: "./assets/items/descarte_mouse_item_pequeno_cutout.png",
    needsStrictSafety: false,
    next: "safety",
  },
];

const schoolCatalog = [
  {
    id: "fundamental-2",
    label: "Fundamental II",
    shortLabel: "6º ao 9º ano",
    grades: [
      {
        id: "6-ano",
        label: "6º ano",
        classrooms: [
          { id: "6-a", label: "6º Ano A", students: ["Ana Beatriz", "Caio Martins", "Helena Rocha", "Miguel Santos"] },
          { id: "6-b", label: "6º Ano B", students: ["Arthur Lima", "Clara Nunes", "João Pedro", "Lívia Costa"] },
        ],
      },
      {
        id: "7-ano",
        label: "7º ano",
        classrooms: [
          { id: "7-a", label: "7º Ano A", students: ["Alice Freitas", "Bernardo Alves", "Laura Ribeiro", "Rafael Melo"] },
          { id: "7-b", label: "7º Ano B", students: ["Davi Moreira", "Isabela Gomes", "Lucas Ferreira", "Sofia Cardoso"] },
        ],
      },
      {
        id: "8-ano",
        label: "8º ano",
        classrooms: [
          { id: "8-a", label: "8º Ano A", students: ["Alencar Silva", "Gustavo Braga", "Marco Caparra", "Vitória Ramos"] },
          { id: "8-b", label: "8º Ano B", students: ["Beatriz Souza", "Gabriel Castro", "Manuela Dias", "Theo Oliveira"] },
        ],
      },
      {
        id: "9-ano",
        label: "9º ano",
        classrooms: [
          { id: "9-a", label: "9º Ano A", students: ["Enzo Carvalho", "Giovana Reis", "Pedro Henrique", "Yasmin Lopes"] },
          { id: "9-b", label: "9º Ano B", students: ["Felipe Azevedo", "Júlia Barros", "Matheus Vieira", "Nicole Mendes"] },
        ],
      },
    ],
  },
  {
    id: "ensino-medio",
    label: "Ensino Médio",
    shortLabel: "1ª à 3ª série",
    grades: [
      {
        id: "1-serie",
        label: "1ª série",
        classrooms: [
          { id: "1-a", label: "1ª Série A", students: ["Amanda Torres", "Bruno Farias", "Eduarda Monteiro", "Henrique Moraes"] },
          { id: "1-b", label: "1ª Série B", students: ["Daniela Peixoto", "Leonardo Cunha", "Mariana Teixeira", "Samuel Correia"] },
        ],
      },
      {
        id: "2-serie",
        label: "2ª série",
        classrooms: [
          { id: "2-a", label: "2ª Série A", students: ["Bianca Martins", "Guilherme Almeida", "Larissa Pires", "Murilo Araújo"] },
          { id: "2-b", label: "2ª Série B", students: ["Carolina Neves", "Igor Campos", "Natália Brito", "Vitor Hugo"] },
        ],
      },
      {
        id: "3-serie",
        label: "3ª série",
        classrooms: [
          { id: "3-a", label: "3ª Série A", students: ["Camila Rezende", "Gustavo Neri", "Luana Prado", "Rodrigo Paiva"] },
          { id: "3-b", label: "3ª Série B", students: ["Cecília Andrade", "Diego Tavares", "Fernanda Luz", "Renan Xavier"] },
        ],
      },
    ],
  },
];

const keyboardRows = [
  ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
  ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
  ["Z", "X", "C", "V", "B", "N", "M"],
];

function selectedSegment() {
  return schoolCatalog.find((segment) => segment.id === kioskState.session.segment) ?? null;
}

function selectedGrade() {
  return selectedSegment()?.grades.find((grade) => grade.id === kioskState.session.grade) ?? null;
}

function selectedClassroom() {
  return selectedGrade()?.classrooms.find((classroom) => classroom.id === kioskState.session.classroom) ?? null;
}

function selectionButton(id, label, detail, field, selectedId) {
  return `
    <button class="selection-button ${selectedId === id ? "selected" : ""}" data-${field}="${id}">
      <span class="selection-copy">
        <strong>${label}</strong>
        <small>${detail}</small>
      </span>
      ${arrowIcon("right")}
    </button>
  `;
}

function normalizeSearch(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleUpperCase("pt-BR");
}

function filteredStudents() {
  const students = selectedClassroom()?.students ?? [];
  const query = normalizeSearch(kioskState.session.studentQuery);
  return students
    .slice()
    .sort((a, b) => a.localeCompare(b, "pt-BR"))
    .filter((student) => !query || normalizeSearch(student).includes(query));
}

function studentResults(students) {
  if (!students.length) {
    return `<div class="student-empty student-empty--missing">Não achei esse nome. Tente apagar uma letra.</div>`;
  }
  return students.map((student) => `
    <button class="student-result ${kioskState.session.student === student ? "selected" : ""}" data-student="${student}">
      <span>${student}</span>
      ${arrowIcon("right")}
    </button>
  `).join("");
}

function alphabetKeyboard() {
  return `
    <div class="alpha-keyboard" aria-label="Teclado alfabético">
      ${keyboardRows.map((row, rowIndex) => `
        <div class="alpha-row alpha-row--${rowIndex + 1}">
          ${row.map((key) => `<button class="alpha-key" data-search-key="${key}">${key}</button>`).join("")}
          ${rowIndex === keyboardRows.length - 1
            ? `<button class="alpha-key alpha-key--delete" data-search-key="Apagar" aria-label="Apagar letra">${backspaceIcon()}</button>`
            : ""}
        </div>
      `).join("")}
      <div class="alpha-row alpha-row--actions">
        <button class="alpha-key alpha-key--space" data-search-key="Espaço">Espaço</button>
      </div>
    </div>
  `;
}

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
    id: "identity-mode",
    label: "Participação",
    render: () => `
      <section class="screen screen--big screen--stack-action screen--identity-mode">
        ${topbar("Participação")}
        <div class="content-zone content-zone--big">
          ${talk(assets.b1n, "Como quer participar?", "big character-joinha")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-mode="student">Quero BinCoins</button>
          <button class="secondary-action" data-mode="classOnly">Só pontuar pra turma</button>
        </div>
      </section>
    `,
  },
  {
    id: "segment",
    label: "Segmento",
    render: () => `
      <section class="screen screen--corner screen--no-action screen--selection">
        ${topbar("Segmento")}
        <div class="content-zone content-zone--corner">
          ${talk(assets.b1nCorner, "Qual é o seu segmento?", "corner")}
          <div class="selection-list selection-list--segments">
            ${schoolCatalog.map((segment) => selectionButton(
              segment.id,
              segment.label,
              segment.shortLabel,
              "segment",
              kioskState.session.segment,
            )).join("")}
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "grade",
    label: "Série",
    render: () => {
      const segment = selectedSegment();
      return `
        <section class="screen screen--corner screen--no-action screen--selection">
          ${topbar("Série")}
          <div class="content-zone content-zone--corner">
            ${talk(assets.b1nDoubtCorner, "Em qual série você está?", "corner character-doubt")}
            <div class="selection-grid selection-grid--grades">
              ${(segment?.grades ?? []).map((grade) => selectionButton(
                grade.id,
                grade.label,
                segment.label,
                "grade",
                kioskState.session.grade,
              )).join("")}
            </div>
          </div>
        </section>
      `;
    },
  },
  {
    id: "classroom",
    label: "Turma",
    render: () => {
      const grade = selectedGrade();
      return `
        <section class="screen screen--corner screen--no-action screen--selection">
          ${topbar("Turma")}
          <div class="content-zone content-zone--corner">
            ${talk(assets.b1nCorner, "Agora, toque na sua turma.", "corner")}
            <div class="selection-list selection-list--classrooms">
              ${(grade?.classrooms ?? []).map((classroom) => selectionButton(
                classroom.id,
                classroom.label,
                grade.label,
                "classroom",
                kioskState.session.classroom,
              )).join("")}
            </div>
          </div>
        </section>
      `;
    },
  },
  {
    id: "student-search",
    label: "Aluno",
    render: () => {
      const students = filteredStudents();
      return `
        <section class="screen screen--corner screen--no-action screen--student-search ${kioskState.session.studentKeyboardOpen ? "is-searching" : ""}" data-search-screen>
          ${topbar("Aluno")}
          <div class="content-zone content-zone--corner">
            ${talk(assets.b1nDoubtCorner, "Busque ou escolha seu nome.", "corner character-doubt")}
            <div class="student-search-box ${kioskState.session.studentKeyboardOpen ? "active" : ""} ${kioskState.session.studentQuery ? "has-query" : ""}" data-search-toggle role="button" aria-label="Busca de aluno" tabindex="0">
              <span>${kioskState.session.studentQuery || "Digite seu nome..."}</span>
              ${kioskState.session.studentQuery
                ? `<button class="search-clear" data-search-clear aria-label="Limpar busca">${closeIcon()}</button>`
                : `<span class="search-icon" aria-hidden="true">${searchIcon()}</span>`}
            </div>
            <div class="student-results" aria-live="polite">
              ${studentResults(students)}
            </div>
            ${kioskState.session.studentKeyboardOpen ? alphabetKeyboard() : ""}
          </div>
        </section>
      `;
    },
  },
  {
    id: "pin",
    label: "PIN",
    render: () => `
      <section class="screen screen--corner screen--no-action screen--pin">
        ${topbar("PIN")}
        <div class="content-zone content-zone--corner">
          ${talk(assets.b1nPrivacyCorner, "Digite seu PIN. Eu não olho.", "corner privacy-guide character-privacy")}
          <div class="pin-display">
            ${[0, 1, 2, 3].map((index) => `<span class="pin-dot ${index < kioskState.session.pinDigits.length ? "filled" : ""}"></span>`).join("")}
          </div>
          <div class="pin-pad">
            ${["1", "2", "3", "4", "5", "6", "7", "8", "9", "Apagar", "0", "OK"].map((key) => `
              <button class="key ${["Apagar", "OK"].includes(key) ? "key-action" : ""} ${key === "OK" && kioskState.session.pinDigits.length < 4 ? "key-disabled" : ""}" data-pin="${key}" ${key === "Apagar" ? 'aria-label="Apagar número"' : ""} ${key === "OK" && kioskState.session.pinDigits.length < 4 ? "disabled" : ""}>${key === "Apagar" ? backspaceIcon() : key}</button>
            `).join("")}
          </div>
          <div class="pin-hint ${kioskState.session.pinWarning ? "show" : ""}">Digite 4 números.</div>
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
          <button class="primary-action" data-insert-confirm>Pronto, coloquei</button>
        </div>
      </section>
    `,
  },
  {
    id: "safety",
    label: "Segurança e mão",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--safety screen--safety-combined">
        ${topbar("Segurança")}
        <div class="content-zone content-zone--corner content-zone--safety">
          ${talk(assets.b1nIdeaCorner, "Antes de fechar: segurança primeiro.", "corner character-idea")}
          <div class="safety-card">
            <strong>Confirme comigo</strong>
            <div class="safety-row"><span>1</span><p>Minha mão está fora da abertura.</p></div>
            <div class="safety-row"><span>2</span><p>O item não está vazando nem estufado.</p></div>
            <p class="safety-note">Se houver vazamento, inchaço ou dano, chame um professor.</p>
          </div>
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-safety="safe">Tudo seguro</button>
          <button class="alert-action" data-safety="unsafe">Chamar professor</button>
        </div>
      </section>
    `,
  },
  {
    id: "door-progress",
    label: "Preparando câmera",
    render: () => `
      <section class="screen screen--corner screen--no-action screen--physical screen--checking screen--door-progress">
        ${topbar("Porta")}
        <div class="content-zone content-zone--physical">
          ${talk(assets.b1nIdeaCorner, "Preparando para escanear.", "corner character-idea")}
          ${processSignal(
            "door",
            "Preparando a câmera",
            "A porta fecha automaticamente. Aguarde um instante.",
            "Mecanismo simulado",
            true,
          )}
        </div>
      </section>
    `,
  },
  {
    id: "capture",
    label: "Captura",
    render: () => `
      <section class="screen screen--camera screen--no-action">
        ${topbar("Câmera")}
        <div class="content-zone content-zone--capture">
          ${talk(assets.b1nAnalyze, "Vou olhar por dentro rapidinho.", "big camera-talk character-analyze")}
          <div class="camera-preview" aria-label="Preview da câmera interna">
            <div class="camera-bar"><span>Câmera interna</span><strong class="camera-live">AO VIVO</strong></div>
            <div class="camera-frame">
              <div class="camera-grid" aria-hidden="true"></div>
              <img class="camera-item" src="${itemOptions.find((item) => item.id === "cable")?.cutout ?? itemOptions[0].image}" alt="Item dentro da câmera" />
              <div class="scan-line" aria-hidden="true"></div>
              <span class="camera-label">Item sendo identificado...</span>
            </div>
          </div>
        </div>
      </section>
    `,
  },
  {
    id: "analyzing",
    label: "Análise",
    render: () => `
      <section class="screen screen--big screen--stack-action screen--analyzing">
        ${topbar("Análise")}
        <div class="content-zone content-zone--big content-zone--analysis">
          ${talk(assets.b1nAnalyze, "Estou reconhecendo o item.", "big analysis-talk character-analyze")}
        </div>
        <div class="action-zone action-zone--stack analysis-status-zone">
          <div class="progress"><span></span></div>
          ${simulationBadge("IA simulada")}
        </div>
      </section>
    `,
  },
  {
    id: "recognized",
    label: "Reconhecido",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--item-focus screen--recognized">
        ${topbar("Reconhecimento")}
        <div class="content-zone content-zone--item-focus">
          ${talk(assets.b1nCorner, "Encontrei isto. Vamos conferir?", "corner")}
          ${itemSummary("Item reconhecido")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-recognition-confirm>Está certo</button>
          <button class="secondary-action" data-jump="correction-menu">Corrigir</button>
        </div>
      </section>
    `,
  },
  {
    id: "correction-menu",
    label: "Correção",
    render: () => `
      <section class="screen screen--corner screen--stack-action screen--correction-menu">
        ${topbar("Correção")}
        <div class="content-zone content-zone--correction">
          ${talk(assets.b1nDoubtCorner, "O que precisa mudar?", "corner character-doubt")}
          <div class="correction-options">
            <button class="correction-option" data-correction-target="item">
              <span class="correction-option-icon">${editIcon()}</span>
              <span><strong>Corrigir item</strong><small>${kioskState.session.recognizedItem?.title ?? "Item eletrônico"}</small></span>
              ${arrowIcon("right")}
            </button>
            <button class="correction-option" data-correction-target="quantity">
              <span class="correction-option-icon correction-option-icon--quantity">${kioskState.session.quantity}</span>
              <span><strong>Corrigir quantidade</strong><small>De 1 a 9 itens</small></span>
              ${arrowIcon("right")}
            </button>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-review>Pronto, revisar</button>
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
          ${talk(assets.b1nIdeaCorner, "Qual item aparece na foto?", "corner character-idea")}
          <div class="correction-item-list">
            ${itemOptions.map((item) => `
              <button class="correction-item ${kioskState.session.draftRecognizedItem?.id === item.id ? "selected" : ""}" data-correct-item="${item.id}">
                <span class="correction-item-media"><img src="${item.cutout ?? item.image}" alt="" /></span>
                <span><strong>${item.title}</strong><small>${item.subtitle}</small></span>
                <span class="selection-mark" aria-hidden="true"></span>
              </button>
            `).join("")}
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-apply-correction>Aplicar correção</button>
        </div>
      </section>
    `,
  },
  {
    id: "correct-quantity",
    label: "Corrigir quantidade",
    render: () => `
      <section class="screen screen--corner screen--correct-quantity">
        ${topbar("Quantidade")}
        <div class="content-zone content-zone--quantity">
          ${talk(assets.b1nIdeaCorner, "Quantos itens foram colocados?", "corner character-idea")}
          <div class="quantity-stepper" aria-label="Quantidade de itens">
            <button data-quantity-step="-1" aria-label="Diminuir quantidade" ${kioskState.session.draftQuantity <= 1 ? "disabled" : ""}>${minusIcon()}</button>
            <div class="quantity-value"><strong>${kioskState.session.draftQuantity}</strong><span>${kioskState.session.draftQuantity === 1 ? "item" : "itens"}</span></div>
            <button data-quantity-step="1" aria-label="Aumentar quantidade" ${kioskState.session.draftQuantity >= 9 ? "disabled" : ""}>${plusIcon()}</button>
          </div>
          <div class="quantity-item">
            <span class="quantity-item-media"><img src="${kioskState.session.draftRecognizedItem?.cutout ?? kioskState.session.draftRecognizedItem?.image ?? ""}" alt="" /></span>
            <span><small>Item reconhecido</small><strong>${kioskState.session.draftRecognizedItem?.title ?? "Item eletrônico"}</strong></span>
          </div>
        </div>
        <div class="action-zone">
          <button class="primary-action" data-apply-correction>Aplicar correção</button>
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
          ${talk(assets.b1nCorner, "Confira antes de liberar o descarte.", "corner")}
          ${itemSummary("Seu descarte")}
        </div>
        <div class="action-zone action-zone--stack">
          <button class="primary-action" data-discard-confirm>Confirmar descarte</button>
          <button class="secondary-action" data-jump="correction-menu">Corrigir</button>
        </div>
      </section>
    `,
  },
  {
    id: "computing",
    label: "Computando descarte",
    render: () => `
      <section class="screen screen--corner screen--no-action screen--physical screen--checking screen--mechanism">
        ${topbar("Descarte")}
        <div class="content-zone content-zone--physical">
          ${talk(assets.b1nIdeaCorner, "Estamos computando seu descarte.", "corner character-idea")}
          ${processSignal("record", "Só mais um instante", "O item está sendo confirmado e registrado.", "Processo simulado", true)}
        </div>
      </section>
    `,
  },
  {
    id: "success",
    label: "Resultado",
    render: () => `
      <section class="screen screen--big screen--success screen--success--${kioskState.session.mode}">
        ${topbar("Concluído")}
        <div class="content-zone content-zone--success">
          ${talk(assets.b1nReward, "Boa! Descarte confirmado.", "big character-reward success-talk")}
          <div class="reward-list">
            <div class="metric metric--class"><span>Pontos da turma</span><strong class="score-gradient"><span class="reward-number">+${kioskState.session.reward.classPoints}</span><span class="reward-unit"> pontos</span></strong></div>
            ${kioskState.session.mode === "student"
              ? `<div class="metric metric--student"><span>Seus BinCoins</span><strong class="score-gradient"><span class="reward-number">+${kioskState.session.reward.binCoins}</span><span class="reward-unit"> BinCoins</span></strong></div>`
              : ""}
            ${simulationBadge("Registro simulado")}
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

function createSession() {
  return {
    mode: "student",
    segment: null,
    grade: null,
    classroom: null,
    studentQuery: "",
    studentKeyboardOpen: false,
    student: null,
    pinDigits: "",
    pinWarning: false,
    safetyConfirmed: false,
    itemInserted: false,
    handConfirmed: false,
    doorStatus: "idle",
    captureStatus: "idle",
    analysisStatus: "idle",
    recognizedItem: null,
    quantity: 1,
    draftRecognizedItem: null,
    draftQuantity: null,
    reviewConfirmed: false,
    mechanismStatus: "idle",
    dropStatus: "idle",
    registrationStatus: "idle",
    processingStatus: "idle",
    reward: {
      classPoints: 20,
      binCoins: 8,
    },
  };
}

const kioskState = {
  screenId: "sleep",
  history: [],
  session: createSession(),
  transitionTimer: null,
};

function screenIndex(id = kioskState.screenId) {
  const index = screens.findIndex((screen) => screen.id === id);
  return index >= 0 ? index : 0;
}

function activeScreen() {
  return screens[screenIndex()];
}

function topbar(step) {
  const currentIndex = screenIndex();
  const lockedScreens = ["computing", "success"];
  const canGoBack = currentIndex > 1
    && activeScreen().id !== "sleep"
    && !lockedScreens.includes(activeScreen().id);
  return `
    <div class="topbar">
      ${canGoBack ? `<button class="back-button" data-back aria-label="Voltar"><svg class="back-icon" aria-hidden="true" viewBox="0 0 24 24"><path d="M15 6L9 12L15 18" /><path d="M10 12H20" /></svg></button>` : `<span class="back-placeholder" aria-hidden="true"></span>`}
      <img class="logo" src="${assets.logo}" alt="BinGo" />
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

function backspaceIcon() {
  return `
    <svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">
      <path d="M9 7L4 12L9 17H20V7H9Z" />
      <path d="M12 10L16 14M16 10L12 14" />
    </svg>
  `;
}

function searchIcon() {
  return `
    <svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">
      <circle cx="11" cy="11" r="6" />
      <path d="M16 16L21 21" />
    </svg>
  `;
}

function closeIcon() {
  return `
    <svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">
      <path d="M7 7L17 17M17 7L7 17" />
    </svg>
  `;
}

function editIcon() {
  return `
    <svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">
      <path d="M4 20H8L19 9L15 5L4 16V20Z" />
      <path d="M13.5 6.5L17.5 10.5" />
    </svg>
  `;
}

function minusIcon() {
  return `
    <svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">
      <path d="M5 12H19" />
    </svg>
  `;
}

function plusIcon() {
  return `
    <svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">
      <path d="M5 12H19M12 5V19" />
    </svg>
  `;
}

function checkIcon() {
  return `
    <svg class="control-icon" aria-hidden="true" viewBox="0 0 24 24">
      <path d="M5 12.5L9.5 17L19 7.5" />
    </svg>
  `;
}

function statusIcon(type) {
  const paths = {
    hand: `
      <path d="M21 16c0 4.42-3.58 8-8 8c-3.26 0-6.19-1.99-7.4-5.02l-3.03-7.61a1 1 0 0 1 1.24-1.32l.79.26c.56.18 1.02.61 1.24 1.16l1.28 3.21c.08.2.26.32.46.32H8V3.25a1.25 1.25 0 0 1 2.5 0v8.25c0 .28.22.5.5.5s.5-.22.5-.5V1.25a1.25 1.25 0 0 1 2.5 0V11.5c0 .28.22.5.5.5s.5-.22.5-.5V2.75a1.25 1.25 0 0 1 2.5 0v8.75c0 .28.22.5.5.5s.5-.22.5-.5V5.75a1.25 1.25 0 0 1 2.5 0V16z" />
    `,
    door: `
      <rect x="5" y="3" width="14" height="18" rx="2" />
      <path d="M9 7h6v10H9z" />
      <circle cx="13.5" cy="12" r=".7" />
    `,
    warning: `
      <path d="M12 3L22 20H2L12 3Z" />
      <path d="M12 9V14" />
      <path d="M12 17.5V17.6" />
    `,
    mechanism: `
      <path d="M4 8H20V18H4Z" />
      <path d="M7 12L12 16L17 12" />
      <path d="M8 5H16" />
    `,
    drop: `
      <path d="M6 18H18" />
      <path d="M12 4V15" />
      <path d="M8 11L12 15L16 11" />
    `,
    record: `
      <path d="M6 4H18V20H6Z" />
      <path d="M9 8H15M9 12H15M9 16H13" />
    `,
  };
  return `<span class="status-icon status-icon--${type}"><svg aria-hidden="true" viewBox="0 0 24 24">${paths[type]}</svg></span>`;
}

function simulationBadge(label) {
  return `<span class="simulation-badge"><span aria-hidden="true"></span>${label}</span>`;
}

function processSignal(type, title, detail, badge = "", checking = false) {
  return `
    <div class="process-signal ${checking ? "is-checking" : ""}">
      ${statusIcon(type)}
      <strong>${title}</strong>
      <span class="process-detail">${detail}</span>
      ${badge ? simulationBadge(badge) : ""}
    </div>
  `;
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
  const item = kioskState.session.recognizedItem;
  return `
    <div class="item-focus">
      <span class="item-focus-label">${label}</span>
      <span class="item-focus-media"><img src="${item?.cutout ?? item?.image ?? ""}" alt="" /></span>
      <div class="item-focus-footer">
        <strong>${item?.title ?? "Item eletrônico"}</strong>
        <span class="item-focus-quantity"><small>Quantidade</small><b>${kioskState.session.quantity}</b></span>
      </div>
    </div>
  `;
}

function render() {
  cancelActiveTransition();
  const kiosk = document.querySelector("#kiosk");
  const screenList = document.querySelector("#screenList");
  const currentIndex = screenIndex();
  kiosk.innerHTML = activeScreen().render();
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
      selectMode(button.dataset.mode);
    });
  });

  document.querySelectorAll("[data-segment]").forEach((button) => {
    button.addEventListener("click", () => selectSegment(button.dataset.segment));
  });

  document.querySelectorAll("[data-grade]").forEach((button) => {
    button.addEventListener("click", () => selectGrade(button.dataset.grade));
  });

  document.querySelectorAll("[data-classroom]").forEach((button) => {
    button.addEventListener("click", () => selectClassroom(button.dataset.classroom));
  });

  document.querySelectorAll("[data-search-key]").forEach((button) => {
    button.addEventListener("click", () => handleSearchKey(button.dataset.searchKey));
  });

  document.querySelectorAll("[data-search-toggle]").forEach((searchBox) => {
    searchBox.addEventListener("click", (event) => {
      if (event.target.closest("[data-search-clear]")) {
        return;
      }
      kioskState.session.studentKeyboardOpen = true;
      render();
    });
    searchBox.addEventListener("keydown", (event) => {
      if (["Enter", " "].includes(event.key)) {
        event.preventDefault();
        kioskState.session.studentKeyboardOpen = true;
        render();
      }
    });
  });

  document.querySelectorAll("[data-search-clear]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      clearStudentSearch();
    });
  });

  document.querySelectorAll("[data-student]").forEach((button) => {
    button.addEventListener("click", () => selectStudent(button.dataset.student));
  });

  document.querySelectorAll("[data-pin]").forEach((button) => {
    button.addEventListener("click", () => handlePin(button.dataset.pin));
  });

  document.querySelectorAll("[data-safety]").forEach((button) => {
    button.addEventListener("click", () => handleSafety(button.dataset.safety));
  });

  document.querySelectorAll("[data-insert-confirm]").forEach((button) => {
    button.addEventListener("click", confirmInsertion);
  });

  document.querySelectorAll("[data-recognition-confirm]").forEach((button) => {
    button.addEventListener("click", openReview);
  });

  document.querySelectorAll("[data-correction-target]").forEach((button) => {
    button.addEventListener("click", () => chooseCorrectionTarget(button.dataset.correctionTarget));
  });

  document.querySelectorAll("[data-correct-item]").forEach((button) => {
    button.addEventListener("click", () => correctRecognizedItem(button.dataset.correctItem));
  });

  document.querySelectorAll("[data-quantity-step]").forEach((button) => {
    button.addEventListener("click", () => changeQuantity(Number(button.dataset.quantityStep)));
  });

  document.querySelectorAll("[data-apply-correction]").forEach((button) => {
    button.addEventListener("click", applyCorrection);
  });

  document.querySelectorAll("[data-review]").forEach((button) => {
    button.addEventListener("click", openReview);
  });

  document.querySelectorAll("[data-discard-confirm]").forEach((button) => {
    button.addEventListener("click", confirmDiscard);
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

  document.querySelectorAll("[data-search-screen]").forEach((screen) => {
    screen.addEventListener("click", (event) => {
      if (!kioskState.session.studentKeyboardOpen) {
        return;
      }
      if (event.target.closest("[data-search-toggle], .alpha-keyboard, [data-student], [data-back]")) {
        return;
      }
      kioskState.session.studentKeyboardOpen = false;
      render();
    });
  });

  document.querySelectorAll("[data-screen]").forEach((button) => {
    button.addEventListener("click", () => {
      kioskState.screenId = screens[Number(button.dataset.screen)]?.id ?? "sleep";
      render();
    });
  });

  document.querySelectorAll("img").forEach((image) => {
    image.setAttribute("draggable", "false");
  });

  scheduleActiveTransition();
}

function next() {
  goToIndex(Math.min(screenIndex() + 1, screens.length - 1));
}

function previous() {
  back();
}

function jump(id) {
  const found = screens.findIndex((screen) => screen.id === id);
  if (found >= 0 && canEnterScreen(id)) {
    if (id === "sleep") {
      kioskState.session = createSession();
      kioskState.history = [];
      kioskState.screenId = id;
      render();
      return;
    }
    goToIndex(found);
  }
}

function goToIndex(index) {
  const currentIndex = screenIndex();
  if (index === currentIndex) {
    return;
  }
  kioskState.history.push(activeScreen().id);
  kioskState.screenId = screens[index]?.id ?? kioskState.screenId;
  render();
}

function replaceScreen(id) {
  const found = screens.findIndex((screen) => screen.id === id);
  if (found < 0 || !canEnterScreen(id)) {
    return;
  }
  kioskState.screenId = id;
  render();
}

function back() {
  if (["computing", "success"].includes(kioskState.screenId)) {
    return;
  }
  if (["correct-item", "correct-quantity"].includes(kioskState.screenId)) {
    discardCorrectionDraft();
  }
  const previousScreenId = kioskState.history.pop();
  if (previousScreenId === undefined) {
    return;
  }
  if (screenIndex(previousScreenId) <= screenIndex("safety")) {
    kioskState.session.doorStatus = "idle";
    kioskState.session.captureStatus = "idle";
  }
  kioskState.screenId = previousScreenId;
  kioskState.session.pinWarning = false;
  render();
}

function canEnterScreen(id) {
  const session = kioskState.session;
  if (id === "insert") {
    return Boolean(session.classroom);
  }
  if (id === "safety") {
    return session.itemInserted;
  }
  if (id === "door-progress") {
    return session.itemInserted && session.handConfirmed && session.safetyConfirmed;
  }
  if (["capture", "analyzing", "recognized"].includes(id)) {
    return session.doorStatus === "closed";
  }
  if (["correction-menu", "correct-item", "correct-quantity", "review"].includes(id)) {
    return session.analysisStatus === "complete" && Boolean(session.recognizedItem);
  }
  if (id === "computing") {
    return session.reviewConfirmed;
  }
  if (id === "success") {
    return session.processingStatus === "complete" && session.registrationStatus === "complete";
  }
  return true;
}

function cancelActiveTransition() {
  if (kioskState.transitionTimer !== null) {
    clearTimeout(kioskState.transitionTimer);
    kioskState.transitionTimer = null;
  }
}

function scheduleActiveTransition() {
  const transitions = {
    "door-progress": {
      delay: 3200,
      run: () => {
        kioskState.session.doorStatus = "closed";
        kioskState.session.captureStatus = "capturing";
        replaceScreen("capture");
      },
    },
    capture: {
      delay: 2200,
      run: () => {
        kioskState.session.captureStatus = "complete";
        kioskState.session.analysisStatus = "analyzing";
        replaceScreen("analyzing");
      },
    },
    analyzing: {
      delay: 2600,
      run: () => {
        kioskState.session.analysisStatus = "complete";
        kioskState.session.recognizedItem = itemOptions.find((item) => item.id === "cable") ?? itemOptions[0];
        kioskState.session.quantity = 1;
        replaceScreen("recognized");
      },
    },
    computing: {
      delay: 4500,
      run: () => {
        kioskState.session.mechanismStatus = "complete";
        kioskState.session.dropStatus = "complete";
        kioskState.session.registrationStatus = "complete";
        kioskState.session.processingStatus = "complete";
        replaceScreen("success");
      },
    },
    success: {
      delay: 6000,
      run: () => jump("sleep"),
    },
  };
  const transition = transitions[kioskState.screenId];
  if (!transition) {
    return;
  }
  kioskState.transitionTimer = setTimeout(() => {
    kioskState.transitionTimer = null;
    transition.run();
  }, transition.delay);
}

function selectMode(mode) {
  kioskState.session.mode = mode === "classOnly" ? "classOnly" : "student";
  kioskState.session.segment = null;
  kioskState.session.grade = null;
  kioskState.session.classroom = null;
  kioskState.session.studentQuery = "";
  kioskState.session.studentKeyboardOpen = false;
  kioskState.session.student = null;
  kioskState.session.pinDigits = "";
  jump("segment");
}

function selectSegment(segmentId) {
  kioskState.session.segment = segmentId;
  kioskState.session.grade = null;
  kioskState.session.classroom = null;
  kioskState.session.studentQuery = "";
  kioskState.session.studentKeyboardOpen = false;
  kioskState.session.student = null;
  kioskState.session.pinDigits = "";
  jump("grade");
}

function selectGrade(gradeId) {
  kioskState.session.grade = gradeId;
  kioskState.session.classroom = null;
  kioskState.session.studentQuery = "";
  kioskState.session.studentKeyboardOpen = false;
  kioskState.session.student = null;
  kioskState.session.pinDigits = "";
  jump("classroom");
}

function selectClassroom(classroomId) {
  kioskState.session.classroom = classroomId;
  kioskState.session.studentQuery = "";
  kioskState.session.studentKeyboardOpen = false;
  kioskState.session.student = null;
  kioskState.session.pinDigits = "";
  jump(kioskState.session.mode === "classOnly" ? "insert" : "student-search");
}

function handleSearchKey(key) {
  kioskState.session.student = null;
  if (key === "Apagar") {
    kioskState.session.studentQuery = kioskState.session.studentQuery.slice(0, -1);
  } else if (key === "Espaço") {
    if (kioskState.session.studentQuery && !kioskState.session.studentQuery.endsWith(" ")) {
      kioskState.session.studentQuery += " ";
    }
  } else if (kioskState.session.studentQuery.length < 24) {
    kioskState.session.studentQuery += key;
  }
  render();
}

function clearStudentSearch() {
  kioskState.session.studentQuery = "";
  kioskState.session.student = null;
  render();
}

function selectStudent(student) {
  if (!selectedClassroom()?.students.includes(student)) {
    return;
  }
  kioskState.session.student = student;
  kioskState.session.studentKeyboardOpen = false;
  kioskState.session.pinDigits = "";
  jump("pin");
}

function resetPhysicalSession() {
  kioskState.session.safetyConfirmed = false;
  kioskState.session.itemInserted = false;
  kioskState.session.handConfirmed = false;
  kioskState.session.doorStatus = "idle";
  kioskState.session.captureStatus = "idle";
  kioskState.session.analysisStatus = "idle";
  kioskState.session.recognizedItem = null;
  kioskState.session.quantity = 1;
  discardCorrectionDraft();
  kioskState.session.reviewConfirmed = false;
  kioskState.session.mechanismStatus = "idle";
  kioskState.session.dropStatus = "idle";
  kioskState.session.registrationStatus = "idle";
  kioskState.session.processingStatus = "idle";
}

function handleSafety(result) {
  if (result === "unsafe") {
    kioskState.session.safetyConfirmed = false;
    kioskState.session.handConfirmed = false;
    jump("teacher");
    return;
  }
  kioskState.session.safetyConfirmed = true;
  kioskState.session.handConfirmed = true;
  kioskState.session.doorStatus = "processing";
  jump("door-progress");
}

function confirmInsertion() {
  resetPhysicalSession();
  kioskState.session.itemInserted = true;
  jump("safety");
}

function openReview() {
  if (!kioskState.session.recognizedItem) {
    return;
  }
  jump("review");
}

function chooseCorrectionTarget(target) {
  if (!["item", "quantity"].includes(target)) {
    return;
  }
  kioskState.session.draftRecognizedItem = kioskState.session.recognizedItem;
  kioskState.session.draftQuantity = kioskState.session.quantity;
  jump(target === "item" ? "correct-item" : "correct-quantity");
}

function correctRecognizedItem(itemId) {
  const item = itemOptions.find((option) => option.id === itemId);
  if (!item) {
    return;
  }
  kioskState.session.draftRecognizedItem = item;
  render();
}

function changeQuantity(direction) {
  const currentQuantity = kioskState.session.draftQuantity ?? kioskState.session.quantity;
  const nextQuantity = currentQuantity + direction;
  kioskState.session.draftQuantity = Math.max(1, Math.min(9, nextQuantity));
  render();
}

function applyCorrection() {
  if (!kioskState.session.draftRecognizedItem || kioskState.session.draftQuantity === null) {
    return;
  }
  kioskState.session.recognizedItem = kioskState.session.draftRecognizedItem;
  kioskState.session.quantity = kioskState.session.draftQuantity;
  discardCorrectionDraft();
  if (kioskState.history.at(-1) === "correction-menu") {
    kioskState.history.pop();
  }
  replaceScreen("correction-menu");
}

function discardCorrectionDraft() {
  kioskState.session.draftRecognizedItem = null;
  kioskState.session.draftQuantity = null;
}

function confirmDiscard() {
  if (!kioskState.session.recognizedItem) {
    return;
  }
  kioskState.session.reviewConfirmed = true;
  kioskState.session.processingStatus = "computing";
  kioskState.session.mechanismStatus = "releasing";
  kioskState.session.registrationStatus = "registering";
  jump("computing");
}

function handlePin(key) {
  kioskState.session.pinWarning = false;
  if (key === "Apagar") {
    kioskState.session.pinDigits = kioskState.session.pinDigits.slice(0, -1);
  } else if (key === "OK") {
    if (kioskState.session.pinDigits.length >= 4) {
      jump("insert");
      return;
    }
    kioskState.session.pinWarning = true;
  } else {
    kioskState.session.pinDigits = `${kioskState.session.pinDigits}${key}`.slice(0, 4);
  }
  render();
}

const DEVICE_WIDTH = 390;
const DEVICE_HEIGHT = 669;

function syncDeviceScale() {
  const stage = document.querySelector(".stage");
  const viewport = document.querySelector(".device-viewport");
  const shell = document.querySelector(".device-shell");
  if (!stage || !viewport || !shell) {
    return;
  }

  const stageStyle = getComputedStyle(stage);
  const horizontalPadding =
    Number.parseFloat(stageStyle.paddingLeft) + Number.parseFloat(stageStyle.paddingRight);
  const availableWidth = Math.max(0, window.innerWidth - horizontalPadding);
  const scale = Math.min(1, availableWidth / DEVICE_WIDTH);

  viewport.style.width = `${DEVICE_WIDTH * scale}px`;
  viewport.style.height = `${DEVICE_HEIGHT * scale}px`;
  shell.style.setProperty("--device-scale", String(scale));
}

document.querySelector("#nextBtn")?.addEventListener("click", next);
document.querySelector("#prevBtn")?.addEventListener("click", previous);
document.addEventListener("dragstart", (event) => {
  if (event.target instanceof HTMLImageElement) {
    event.preventDefault();
  }
});
window.addEventListener("resize", syncDeviceScale);
syncDeviceScale();
render();
