const API_BASE_URL = "http://localhost:8000/v1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";

// Chave exposta apenas porque este Ã© um simulador web de desenvolvimento.
// No totem real, a API key deve ficar protegida no serviço local do Edge/Orange Pi.
const MACHINE_API_KEY = "edge-demo-key";

const sectionTitles = {
  "discard-section": "Simulador de descarte",
  "student-section": "Informações do aluno",
  "ranking-section": "Rankings",
};

const discardScreens = {
  start: { id: "discard-screen-start", step: "Tela 1 de 5" },
  mode: { id: "discard-screen-mode", step: "Tela 2 de 5" },
  class: { id: "discard-screen-class", step: "Tela 3A de 5" },
  student: { id: "discard-screen-student", step: "Tela 3B de 5" },
  item: { id: "discard-screen-item", step: "Tela 4 de 5" },
  result: { id: "discard-screen-result", step: "Tela 5 de 5" },
};

const state = {
  context: null,
  rankings: null,
  selectedStudentSummary: null,
  discard: {
    screen: "start",
    mode: null,
    classId: null,
    studentId: null,
    pin: "",
    studentToken: null,
    lastPayload: null,
    lastDeposit: null,
  },
  studentInfo: {
    classId: null,
    studentId: null,
  },
};

const navButtons = document.querySelectorAll(".nav-button");
const sections = document.querySelectorAll(".page-section");
const sectionTitle = document.querySelector("#section-title");
const schoolName = document.querySelector("#school-name");

const discardFlow = document.querySelector("#discard-flow");
const discardStepLabel = document.querySelector("#discard-step-label");
const discardMessage = document.querySelector("#discard-message");
const discardProgressItems = document.querySelectorAll(".totem-progress span");

const discardClassSelect = document.querySelector("#discard-class-select");
const identifiedClassSelect = document.querySelector("#identified-class-select");
const identifiedStudentSelect = document.querySelector("#identified-student-select");
const studentPickerOpen = document.querySelector("#student-picker-open");
const studentPickerSelected = document.querySelector("#student-picker-selected");
const studentPickerDialog = document.querySelector("#student-picker-dialog");
const studentPickerSearch = document.querySelector("#student-picker-search");
const studentPickerList = document.querySelector("#student-picker-list");
const studentPickerClose = document.querySelector("#student-picker-close");
const studentPinInput = document.querySelector("#student-pin");
const itemSizeSelect = document.querySelector("#item-size");
const itemValiditySelect = document.querySelector("#item-validity");
const detectedTypeSelect = document.querySelector("#detected-type");
const resultTitle = document.querySelector("#result-title");
const resultSubtitle = document.querySelector("#result-subtitle");
const discardResultCard = document.querySelector("#discard-result-card");

const studentInfoSelect = document.querySelector("#student-info-select");
const studentInfoClassSelect = document.querySelector("#student-info-class-select");
const studentInfoPickerOpen = document.querySelector("#student-info-picker-open");
const studentInfoPickerSelected = document.querySelector("#student-info-picker-selected");
const studentInfoPickerDialog = document.querySelector("#student-info-picker-dialog");
const studentInfoPickerSearch = document.querySelector("#student-info-picker-search");
const studentInfoPickerList = document.querySelector("#student-info-picker-list");
const studentInfoPickerClose = document.querySelector("#student-info-picker-close");
const studentDetails = document.querySelector("#student-details");
const studentHistory = document.querySelector("#student-history");

const studentRanking = document.querySelector("#student-ranking");
const classRanking = document.querySelector("#class-ranking");

async function apiRequest(path, options = {}) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-Machine-Id": MACHINE_ID,
      "X-Api-Key": MACHINE_API_KEY,
      ...(options.headers || {}),
    },
  });

  if (!response.ok) {
    let message = "Não foi possível concluir a requisição.";
    try {
      const error = await response.json();
      message = error.detail || message;
    } catch {
      message = `${message} Status: ${response.status}`;
    }
    throw new Error(message);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

function loadContext() {
  return apiRequest("/totem/context");
}

function loadStudentSummary(studentId) {
  return apiRequest(`/totem/students/${studentId}/summary`);
}

function loadRankings() {
  return apiRequest("/totem/rankings");
}

function loginTotemStudent(payload) {
  return apiRequest("/totem/students/login", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

function submitDeposit(payload) {
  return apiRequest("/deposits", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

function getClassById(classId) {
  return state.context?.classes.find((classroom) => classroom.id === classId);
}

function getStudentById(studentId) {
  return state.context?.students.find((student) => student.id === studentId);
}

function getStudentsByClass(classId) {
  return (state.context?.students || []).filter((student) => student.class_id === classId);
}

function formatDate(value) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

function setActiveSection(sectionId) {
  sections.forEach((section) => {
    section.classList.toggle("active", section.id === sectionId);
  });

  navButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.section === sectionId);
  });

  sectionTitle.textContent = sectionTitles[sectionId];

  if (sectionId === "ranking-section") {
    refreshRankings();
  }
}

function setDiscardMessage(content, className = "empty-state") {
  discardMessage.className = className;
  discardMessage.innerHTML = content;
}

function setDiscardEnabled(isEnabled) {
  discardFlow.querySelectorAll("button, input, select").forEach((element) => {
    element.disabled = !isEnabled;
  });
}

function renderOptions(selectElement, items, getLabel) {
  selectElement.innerHTML = items
    .map((item) => `<option value="${item.id}">${getLabel(item)}</option>`)
    .join("");
}

function normalizeSearchText(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function getFilteredIdentifiedStudents() {
  const classId = identifiedClassSelect.value || state.discard.classId;
  const students = getStudentsByClass(classId);
  const query = normalizeSearchText(studentPickerSearch.value);

  if (!query) {
    return students;
  }

  return students.filter((student) => normalizeSearchText(student.name).includes(query));
}

function updateStudentPickerLabel() {
  const student = getStudentById(state.discard.studentId);
  studentPickerSelected.textContent = student ? student.name : "Escolher aluno";
}

function renderStudentPickerList() {
  const students = getFilteredIdentifiedStudents();

  if (!students.length) {
    studentPickerList.innerHTML = '<div class="student-picker-empty">Nenhum aluno encontrado para esse filtro.</div>';
    return;
  }

  studentPickerList.innerHTML = students
    .map((student) => {
      const isActive = student.id === state.discard.studentId ? " active" : "";
      return `<button class="student-picker-option${isActive}" type="button" data-student-id="${student.id}">${student.name}</button>`;
    })
    .join("");
}

function openStudentPicker() {
  studentPickerSearch.value = "";
  renderStudentPickerList();
  studentPickerDialog.hidden = false;
  studentPickerSearch.focus();
}

function closeStudentPicker() {
  studentPickerDialog.hidden = true;
  studentPickerOpen.focus();
}

function selectIdentifiedStudent(studentId) {
  state.discard.studentId = studentId;
  identifiedStudentSelect.value = studentId;
  updateStudentPickerLabel();
  closeStudentPicker();
  studentPinInput.focus();
}

function updateStudentInfoPickerLabel() {
  const student = getStudentById(state.studentInfo.studentId);
  studentInfoPickerSelected.textContent = student ? student.name : "Escolher aluno";
}

function getFilteredStudentInfoStudents() {
  const classId = studentInfoClassSelect.value || state.studentInfo.classId;
  const students = getStudentsByClass(classId);
  const query = normalizeSearchText(studentInfoPickerSearch.value);

  if (!query) {
    return students;
  }

  return students.filter((student) => normalizeSearchText(student.name).includes(query));
}

function renderStudentInfoPickerList() {
  const students = getFilteredStudentInfoStudents();

  if (!students.length) {
    studentInfoPickerList.innerHTML = '<div class="student-picker-empty">Nenhum aluno encontrado para esse filtro.</div>';
    return;
  }

  studentInfoPickerList.innerHTML = students
    .map((student) => {
      const isActive = student.id === state.studentInfo.studentId ? " active" : "";
      return `<button class="student-picker-option${isActive}" type="button" data-student-id="${student.id}">${student.name}</button>`;
    })
    .join("");
}

function renderStudentInfoClassOptions() {
  const classes = state.context?.classes || [];
  renderOptions(studentInfoClassSelect, classes, (classroom) => classroom.name);

  if (!state.studentInfo.classId && classes[0]) {
    state.studentInfo.classId = classes[0].id;
  }

  if (state.studentInfo.classId) {
    studentInfoClassSelect.value = state.studentInfo.classId;
  }

  renderStudentInfoStudentOptions();
}

function renderStudentInfoStudentOptions() {
  const classId = studentInfoClassSelect.value || state.studentInfo.classId;
  const students = getStudentsByClass(classId);
  renderOptions(studentInfoSelect, students, (student) => student.name);

  const previousStudentStillVisible = students.some((student) => student.id === state.studentInfo.studentId);
  if (previousStudentStillVisible) {
    studentInfoSelect.value = state.studentInfo.studentId;
  } else {
    state.studentInfo.studentId = null;
    studentInfoSelect.value = "";
  }

  updateStudentInfoPickerLabel();
  renderStudentInfoPickerList();
}

function openStudentInfoPicker() {
  studentInfoPickerSearch.value = "";
  renderStudentInfoPickerList();
  studentInfoPickerDialog.hidden = false;
  studentInfoPickerSearch.focus();
}

function closeStudentInfoPicker() {
  studentInfoPickerDialog.hidden = true;
  studentInfoPickerOpen.focus();
}

async function selectStudentInfoStudent(studentId) {
  state.studentInfo.studentId = studentId;
  studentInfoSelect.value = studentId;
  updateStudentInfoPickerLabel();
  closeStudentInfoPicker();
  await handleStudentInfoChange();
}

function renderDiscardClassOptions() {
  const classes = state.context?.classes || [];
  renderOptions(discardClassSelect, classes, (classroom) => classroom.name);
  renderOptions(identifiedClassSelect, classes, (classroom) => classroom.name);

  if (!state.discard.classId && classes[0]) {
    state.discard.classId = classes[0].id;
  }

  if (state.discard.classId) {
    discardClassSelect.value = state.discard.classId;
    identifiedClassSelect.value = state.discard.classId;
  }

  renderIdentifiedStudentOptions();
}

function renderIdentifiedStudentOptions() {
  const classId = identifiedClassSelect.value || state.discard.classId;
  const students = getStudentsByClass(classId);
  renderOptions(identifiedStudentSelect, students, (student) => student.name);

  const previousStudentStillVisible = students.some((student) => student.id === state.discard.studentId);
  if (previousStudentStillVisible) {
    identifiedStudentSelect.value = state.discard.studentId;
  } else {
    state.discard.studentId = null;
    identifiedStudentSelect.value = "";
  }

  updateStudentPickerLabel();
  renderStudentPickerList();
}

function renderDiscardScreen(screenName) {
  state.discard.screen = screenName;
  const screen = discardScreens[screenName];
  document.querySelectorAll(".discard-screen").forEach((element) => {
    const isActive = element.id === screen.id;
    element.classList.toggle("active", isActive);
    element.hidden = !isActive;
  });

  discardStepLabel.textContent = screen.step;
  const progressIndex = screenName === "start" ? 0 : screenName === "mode" ? 1 : screenName === "item" ? 3 : screenName === "result" ? 4 : 2;
  discardProgressItems.forEach((item, index) => {
    item.classList.toggle("active", index <= progressIndex);
  });
}

function resetDiscardFlow({ keepMessage = false } = {}) {
  state.discard = {
    screen: "start",
    mode: null,
    classId: state.context?.classes[0]?.id || null,
    studentId: null,
    pin: "",
    studentToken: null,
    lastPayload: null,
    lastDeposit: null,
  };
  studentPinInput.value = "";
  studentPickerSearch.value = "";
  studentPickerDialog.hidden = true;
  renderDiscardClassOptions();
  renderDiscardScreen("start");

  if (!keepMessage) {
    setDiscardMessage("Aguardando iní­cio do descarte.");
  }
}

function showModeScreen() {
  renderDiscardScreen("mode");
  setDiscardMessage("Tela 2: escolha se o descarte tera aluno identificado ou somente turma.");
}

function showAnonymousClassScreen() {
  state.discard.mode = "anonymous";
  state.discard.studentId = null;
  discardClassSelect.value = state.discard.classId || discardClassSelect.value;
  renderDiscardScreen("class");
  setDiscardMessage("Tela 3A: selecione a turma para pontuar sem identificar aluno.");
}

function showIdentifiedStudentScreen() {
  state.discard.mode = "identified";
  identifiedClassSelect.value = state.discard.classId || identifiedClassSelect.value;
  renderIdentifiedStudentOptions();
  renderDiscardScreen("student");
  setDiscardMessage("Tela 3B: selecione turma, aluno e PIN de 4 dígitos.");
}

function showItemScreen() {
  renderDiscardScreen("item");
  const className = getClassById(state.discard.classId)?.name || "turma";
  const student = getStudentById(state.discard.studentId);
  const identityText = student ? `${student.name} (${className})` : `sem identificação (${className})`;
  setDiscardMessage(`Tela 4: descarte em nome de <strong>${identityText}</strong>.`);
}

async function validateStudentAndContinue() {
  state.discard.classId = identifiedClassSelect.value;
  state.discard.studentId = identifiedStudentSelect.value;
  state.discard.pin = studentPinInput.value.trim();

  if (!state.discard.classId || !state.discard.studentId) {
    setDiscardMessage("<strong>Selecione turma e aluno para continuar.</strong>", "message error");
    return;
  }

  if (!/^\d{4}$/.test(state.discard.pin)) {
    setDiscardMessage("<strong>PIN inválido.</strong><p>Informe exatamente 4 dígitos.</p>", "message error");
    return;
  }

  try {
    setDiscardEnabled(false);
    setDiscardMessage("Validando PIN do aluno no backend...");
    const result = await loginTotemStudent({
      class_id: state.discard.classId,
      student_id: state.discard.studentId,
      pin: state.discard.pin,
    });
    state.discard.studentId = result.student.id;
    state.discard.studentToken = result.access_token;
    setDiscardMessage("Aluno identificado com PIN correto. Proxima etapa: informar o item.", "message success");
    showItemScreen();
  } catch (error) {
    state.discard.studentToken = null;
    setDiscardMessage(`<strong>Não foi possível identificar o aluno.</strong><p>${error.message}</p>`, "message error");
  } finally {
    setDiscardEnabled(true);
  }
}

function buildDepositPayload() {
  const classId = state.discard.mode === "anonymous" ? discardClassSelect.value : state.discard.classId;
  state.discard.classId = classId;

  return {
    event_id: crypto.randomUUID(),
    student_id: state.discard.mode === "identified" ? state.discard.studentId : null,
    class_id: classId,
    is_valid: itemValiditySelect.value === "valid",
    detected_type: detectedTypeSelect.value,
    size: itemSizeSelect.value,
  };
}

function renderDepositResult(payload, deposit) {
  const refreshedStudent = payload.student_id ? getStudentById(payload.student_id) : null;
  const refreshedClass = getClassById(payload.class_id);
  const validText = payload.is_valid ? "Descarte aceito" : "Item devolvido";
  const statusClass = payload.is_valid ? "success" : "error";

  resultTitle.textContent = validText;
  resultSubtitle.textContent = payload.is_valid
    ? "Pontuação registrada pelo backend."
    : "Nenhum Bin foi gerado para item inválido.";

  discardResultCard.className = `result-summary ${statusClass}`;
  discardResultCard.innerHTML = `
    <div class="metric"><span>Status</span><span>${validText}</span></div>
    <div class="metric"><span>Tipo</span><span>${payload.detected_type || "sem tipo"}</span></div>
    <div class="metric"><span>Tamanho</span><span>${payload.size}</span></div>
    <div class="metric"><span>Aluno</span><span>${refreshedStudent ? refreshedStudent.name : "Sem identificação"}</span></div>
    <div class="metric"><span>Pontos da turma</span><span>${deposit.points_awarded_class} Bins</span></div>
    <div class="metric"><span>Saldo da turma</span><span>${refreshedClass ? `${refreshedClass.points_class_balance} Bins` : "-"}</span></div>
  `;

  if (refreshedStudent) {
    discardResultCard.innerHTML += `
      <div class="metric"><span>Pontos do aluno</span><span>${deposit.points_awarded_student} Bins</span></div>
      <div class="metric"><span>Saldo do aluno</span><span>${refreshedStudent.points_student_balance} Bins</span></div>
    `;
  }

  setDiscardMessage(
    `<strong>${validText}.</strong><p>${refreshedStudent ? `Aluno: ${refreshedStudent.name}. ` : "Sem aluno identificado. "}Turma: ${refreshedClass?.name || "-"}.</p>`,
    `message ${statusClass}`,
  );
}

async function confirmDiscard() {
  const payload = buildDepositPayload();

  if (!payload.class_id) {
    setDiscardMessage("<strong>Selecione uma turma antes de confirmar.</strong>", "message error");
    return;
  }

  try {
    setDiscardEnabled(false);
    setDiscardMessage("Processando descarte no backend...");
    const deposit = await submitDeposit(payload);
    state.discard.lastPayload = payload;
    state.discard.lastDeposit = deposit;
    await refreshAfterDeposit(payload.student_id);
    renderDepositResult(payload, deposit);
    renderDiscardScreen("result");
  } catch (error) {
    setDiscardMessage(`<strong>Erro ao simular descarte.</strong><p>${error.message}</p>`, "message error");
  } finally {
    setDiscardEnabled(true);
  }
}

function handleBackAction() {
  if (state.discard.screen === "mode") {
    resetDiscardFlow();
    return;
  }

  if (state.discard.screen === "class" || state.discard.screen === "student") {
    showModeScreen();
    return;
  }

  if (state.discard.screen === "item") {
    if (state.discard.mode === "anonymous") {
      showAnonymousClassScreen();
    } else {
      showIdentifiedStudentScreen();
    }
  }
}

function handleDiscardAction(action) {
  const actions = {
    start: showModeScreen,
    anonymous: showAnonymousClassScreen,
    identified: showIdentifiedStudentScreen,
    "class-next": () => {
      state.discard.classId = discardClassSelect.value;
      showItemScreen();
    },
    "validate-student": validateStudentAndContinue,
    "confirm-discard": confirmDiscard,
    back: handleBackAction,
    finish: () => resetDiscardFlow(),
    "new-discard": () => {
      resetDiscardFlow({ keepMessage: true });
      showModeScreen();
    },
  };

  actions[action]?.();
}

function renderStudentInfo(summary) {
  if (!summary) {
    studentDetails.innerHTML = '<div class="empty-state">Selecione um aluno para consultar os dados.</div>';
    studentHistory.innerHTML = '<div class="empty-state">Nenhum histórico carregado.</div>';
    return;
  }

  const lastDeposit = summary.recent_deposits[0];
  const lastDepositText = lastDeposit
    ? `${lastDeposit.detected_type || "sem tipo"} (${lastDeposit.size}) - ${
        lastDeposit.is_valid ? `${lastDeposit.points_awarded_student} Bins` : "inválido"
      }`
    : "Nenhum descarte encontrado";

  studentDetails.innerHTML = `
    <div class="metric"><span>Nome</span><span>${summary.student.name}</span></div>
    <div class="metric"><span>Turma</span><span>${summary.student.class_name}</span></div>
    <div class="metric"><span>Saldo atual</span><span>${summary.student.points_student_balance} Bins</span></div>
    <div class="metric"><span>Descartes válidos</span><span>${summary.stats.valid_deposits_count}</span></div>
    <div class="metric"><span>Descartes inválidos</span><span>${summary.stats.invalid_deposits_count}</span></div>
    <div class="metric"><span>Total gerado</span><span>${summary.stats.total_bins_generated} Bins</span></div>
    <div class="metric"><span>Último descarte</span><span>${lastDepositText}</span></div>
  `;

  studentHistory.innerHTML = summary.recent_deposits.length
    ? summary.recent_deposits
        .map(
          (deposit) => `
            <article class="history-item">
              <strong>${deposit.detected_type || "sem tipo"} - ${deposit.size}</strong>
              <small>${deposit.is_valid ? `${deposit.points_awarded_student} Bins gerados` : "Item inválido"} - ${formatDate(deposit.created_at)}</small>
            </article>
          `,
        )
        .join("")
    : '<div class="empty-state">Nenhum descarte para este aluno.</div>';
}

function renderRankings() {
  const rankings = state.rankings;
  if (!rankings) {
    studentRanking.innerHTML = '<li>Rankings ainda não carregados.</li>';
    classRanking.innerHTML = '<li>Rankings ainda não carregados.</li>';
    return;
  }

  studentRanking.innerHTML = rankings.students
    .map(
      (student, index) => `
        <li class="${index < 3 ? "top" : ""}">
          <div class="ranking-row">
            <strong>${student.name}<br><small>${student.class_name}</small></strong>
            <span>${student.points_student_balance} Bins</span>
          </div>
        </li>
      `,
    )
    .join("");

  classRanking.innerHTML = rankings.classes
    .map(
      (classroom, index) => `
        <li class="${index < 3 ? "top" : ""}">
          <div class="ranking-row">
            <strong>${classroom.name}</strong>
            <span>${classroom.points_class_balance} Bins</span>
          </div>
        </li>
      `,
    )
    .join("");
}

function syncSelectedStudentInfo(studentId) {
  if (!studentId) {
    return;
  }

  const student = getStudentById(studentId);
  if (!student) {
    return;
  }

  state.studentInfo.classId = student.class_id;
  state.studentInfo.studentId = student.id;
  studentInfoClassSelect.value = student.class_id;
  renderStudentInfoStudentOptions();
}

async function refreshContext() {
  const previousInfoStudent = state.studentInfo.studentId || studentInfoSelect.value;
  const previousInfoClass = state.studentInfo.classId || studentInfoClassSelect.value;
  const previousDiscardClass = state.discard.classId;
  state.context = await loadContext();
  schoolName.textContent = state.context.school.name;

  const previousStudent = previousInfoStudent ? getStudentById(previousInfoStudent) : null;
  state.studentInfo.classId = previousStudent?.class_id || previousInfoClass || state.context.classes[0]?.id || null;
  state.studentInfo.studentId = previousStudent?.id || null;
  renderStudentInfoClassOptions();

  state.discard.classId = previousDiscardClass || state.context.classes[0]?.id || null;
  renderDiscardClassOptions();
}

async function refreshStudentSummary(studentId = studentInfoSelect.value) {
  if (!studentId) {
    renderStudentInfo(null);
    return;
  }

  const summary = await loadStudentSummary(studentId);
  state.selectedStudentSummary = summary;
  renderStudentInfo(summary);
}

async function refreshRankings() {
  state.rankings = await loadRankings();
  renderRankings();
}

async function refreshAfterDeposit(studentId) {
  await refreshContext();
  syncSelectedStudentInfo(studentId);
  const summaryTarget = studentId || studentInfoSelect.value;
  await Promise.all([refreshRankings(), refreshStudentSummary(summaryTarget)]);
}

async function handleStudentInfoChange() {
  try {
    state.studentInfo.studentId = studentInfoSelect.value;
    updateStudentInfoPickerLabel();
    await refreshStudentSummary(state.studentInfo.studentId);
  } catch (error) {
    studentDetails.innerHTML = `<div class="message error"><strong>Erro ao carregar aluno.</strong><p>${error.message}</p></div>`;
    studentHistory.innerHTML = "";
  }
}

async function init() {
  try {
    setDiscardEnabled(false);
    setDiscardMessage("Carregando dados reais da API...");
    await refreshContext();
    await Promise.all([refreshRankings(), refreshStudentSummary()]);
    resetDiscardFlow();
  } catch (error) {
    schoolName.textContent = "API indisponível";
    setDiscardMessage(
      `<strong>Não foi possível carregar o Totem Simulator.</strong><p>${error.message}</p>`,
      "message error",
    );
    studentDetails.innerHTML = '<div class="empty-state">Verifique se o backend está rodando em localhost:8000.</div>';
    studentHistory.innerHTML = "";
    renderRankings();
  } finally {
    setDiscardEnabled(true);
  }
}

navButtons.forEach((button) => {
  button.addEventListener("click", () => setActiveSection(button.dataset.section));
});

discardFlow.addEventListener("click", (event) => {
  const button = event.target.closest("[data-discard-action]");
  if (!button) {
    return;
  }
  handleDiscardAction(button.dataset.discardAction);
});

discardClassSelect.addEventListener("change", () => {
  state.discard.classId = discardClassSelect.value;
});

identifiedClassSelect.addEventListener("change", () => {
  state.discard.classId = identifiedClassSelect.value;
  renderIdentifiedStudentOptions();
});

identifiedStudentSelect.addEventListener("change", () => {
  state.discard.studentId = identifiedStudentSelect.value;
  updateStudentPickerLabel();
});

studentPickerOpen.addEventListener("click", openStudentPicker);
studentPickerClose.addEventListener("click", closeStudentPicker);

studentPickerDialog.addEventListener("click", (event) => {
  if (event.target === studentPickerDialog) {
    closeStudentPicker();
  }
});

studentPickerSearch.addEventListener("input", renderStudentPickerList);

studentPickerList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-student-id]");
  if (!button) {
    return;
  }
  selectIdentifiedStudent(button.dataset.studentId);
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") {
    return;
  }

  if (!studentPickerDialog.hidden) {
    closeStudentPicker();
  }

  if (!studentInfoPickerDialog.hidden) {
    closeStudentInfoPicker();
  }
});

studentPinInput.addEventListener("input", () => {
  studentPinInput.value = studentPinInput.value.replace(/\D/g, "").slice(0, 4);
});

studentInfoClassSelect.addEventListener("change", () => {
  state.studentInfo.classId = studentInfoClassSelect.value;
  state.studentInfo.studentId = null;
  renderStudentInfoStudentOptions();
  renderStudentInfo(null);
});

studentInfoPickerOpen.addEventListener("click", openStudentInfoPicker);
studentInfoPickerClose.addEventListener("click", closeStudentInfoPicker);

studentInfoPickerDialog.addEventListener("click", (event) => {
  if (event.target === studentInfoPickerDialog) {
    closeStudentInfoPicker();
  }
});

studentInfoPickerSearch.addEventListener("input", renderStudentInfoPickerList);

studentInfoPickerList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-student-id]");
  if (!button) {
    return;
  }
  selectStudentInfoStudent(button.dataset.studentId);
});

studentInfoSelect.addEventListener("change", handleStudentInfoChange);

init();
