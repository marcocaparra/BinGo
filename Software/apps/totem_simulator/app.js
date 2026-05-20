const API_BASE_URL = "http://localhost:8000/v1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";

// Chave exposta apenas porque este é um simulador web de desenvolvimento.
// No totem real, a API key deve ficar protegida no serviço local do Edge/Orange Pi.
const MACHINE_API_KEY = "edge-demo-key";

const sectionTitles = {
  "discard-section": "Simulador de descarte",
  "student-section": "Informações do aluno",
  "ranking-section": "Rankings",
};

const state = {
  context: null,
  rankings: null,
  selectedStudentSummary: null,
};

const navButtons = document.querySelectorAll(".nav-button");
const sections = document.querySelectorAll(".page-section");
const sectionTitle = document.querySelector("#section-title");
const schoolName = document.querySelector("#school-name");

const discardForm = document.querySelector("#discard-form");
const discardStudentSelect = document.querySelector("#discard-student");
const discardClassInput = document.querySelector("#discard-class");
const itemSizeSelect = document.querySelector("#item-size");
const itemValiditySelect = document.querySelector("#item-validity");
const detectedTypeSelect = document.querySelector("#detected-type");
const discardMessage = document.querySelector("#discard-message");

const studentInfoSelect = document.querySelector("#student-info-select");
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

function submitDeposit(payload) {
  return apiRequest("/deposits", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

function getSelectedStudent(selectElement = discardStudentSelect) {
  return state.context?.students.find((student) => student.id === selectElement.value);
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

function setLoadingMessage(message) {
  discardMessage.className = "empty-state";
  discardMessage.textContent = message;
}

function setFormEnabled(isEnabled) {
  discardForm.querySelectorAll("button, input, select").forEach((element) => {
    element.disabled = !isEnabled;
  });
}

function renderStudentOptions() {
  const students = state.context?.students || [];
  const options = students
    .map((student) => `<option value="${student.id}">${student.name}</option>`)
    .join("");

  discardStudentSelect.innerHTML = options;
  studentInfoSelect.innerHTML = options;
}

function updateDiscardClass() {
  const student = getSelectedStudent();
  discardClassInput.value = student?.class_name || "";
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
              <small>${deposit.is_valid ? `${deposit.points_awarded_student} Bins gerados` : "Item inválido"} · ${formatDate(deposit.created_at)}</small>
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

function syncSelectedStudentAcrossSections(studentId) {
  if (discardStudentSelect.value !== studentId) {
    discardStudentSelect.value = studentId;
  }
  if (studentInfoSelect.value !== studentId) {
    studentInfoSelect.value = studentId;
  }
}

async function refreshContext() {
  const previousDiscardStudent = discardStudentSelect.value;
  const previousInfoStudent = studentInfoSelect.value;
  state.context = await loadContext();
  schoolName.textContent = state.context.school.name;
  renderStudentOptions();

  const preferredStudent = previousDiscardStudent || previousInfoStudent || state.context.students[0]?.id;
  if (preferredStudent) {
    discardStudentSelect.value = preferredStudent;
    studentInfoSelect.value = previousInfoStudent || preferredStudent;
  }
  updateDiscardClass();
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
  syncSelectedStudentAcrossSections(studentId);
  updateDiscardClass();
  await Promise.all([refreshRankings(), refreshStudentSummary(studentId)]);
}

async function handleDiscardSubmit(event) {
  event.preventDefault();
  const student = getSelectedStudent();
  if (!student) {
    return;
  }

  const payload = {
    event_id: crypto.randomUUID(),
    student_id: student.id,
    class_id: student.class_id,
    is_valid: itemValiditySelect.value === "valid",
    detected_type: detectedTypeSelect.value,
    size: itemSizeSelect.value,
  };

  try {
    setFormEnabled(false);
    const deposit = await submitDeposit(payload);
    await refreshAfterDeposit(student.id);

    const refreshedStudent = state.context.students.find((item) => item.id === student.id);
    const refreshedClass = state.context.classes.find((item) => item.id === student.class_id);

    if (!payload.is_valid) {
      discardMessage.className = "message error";
      discardMessage.innerHTML = `
        <strong>Item inválido. Nenhum Bin foi gerado.</strong>
        <ul>
          <li>Aluno: ${refreshedStudent.name}</li>
          <li>Turma: ${refreshedStudent.class_name}</li>
          <li>Tipo detectado: ${payload.detected_type}</li>
        </ul>
      `;
      return;
    }

    discardMessage.className = "message success";
    discardMessage.innerHTML = `
      <strong>Descarte registrado pelo backend.</strong>
      <ul>
        <li>Aluno: ${refreshedStudent.name}</li>
        <li>Turma: ${refreshedStudent.class_name}</li>
        <li>Tamanho do item: ${payload.size}</li>
        <li>Tipo detectado: ${payload.detected_type}</li>
        <li>Pontos gerados: ${deposit.points_awarded_student} Bins</li>
        <li>Novo saldo do aluno: ${refreshedStudent.points_student_balance} Bins</li>
        <li>Novo saldo da turma: ${refreshedClass.points_class_balance} Bins</li>
      </ul>
    `;
  } catch (error) {
    discardMessage.className = "message error";
    discardMessage.innerHTML = `<strong>Erro ao simular descarte.</strong><p>${error.message}</p>`;
  } finally {
    setFormEnabled(true);
  }
}

async function handleStudentInfoChange() {
  try {
    await refreshStudentSummary(studentInfoSelect.value);
  } catch (error) {
    studentDetails.innerHTML = `<div class="message error"><strong>Erro ao carregar aluno.</strong><p>${error.message}</p></div>`;
    studentHistory.innerHTML = "";
  }
}

async function init() {
  try {
    setFormEnabled(false);
    setLoadingMessage("Carregando dados reais da API...");
    await refreshContext();
    await Promise.all([refreshRankings(), refreshStudentSummary()]);
    setLoadingMessage("Dados carregados. Simule um descarte para ver o resultado.");
  } catch (error) {
    schoolName.textContent = "API indisponível";
    discardMessage.className = "message error";
    discardMessage.innerHTML = `
      <strong>Não foi possível carregar o Totem Simulator.</strong>
      <p>${error.message}</p>
    `;
    studentDetails.innerHTML = '<div class="empty-state">Verifique se o backend está rodando em localhost:8000.</div>';
    studentHistory.innerHTML = "";
    renderRankings();
  } finally {
    setFormEnabled(true);
  }
}

navButtons.forEach((button) => {
  button.addEventListener("click", () => setActiveSection(button.dataset.section));
});

discardStudentSelect.addEventListener("change", () => {
  updateDiscardClass();
  syncSelectedStudentAcrossSections(discardStudentSelect.value);
  refreshStudentSummary(discardStudentSelect.value);
});
studentInfoSelect.addEventListener("change", handleStudentInfoChange);
discardForm.addEventListener("submit", handleDiscardSubmit);

init();
