const pointsBySize = {
  SMALL: 10,
  MEDIUM: 25,
  LARGE: 50,
};

// Simulação local: estes dados vivem apenas em memória no navegador.
const state = {
  school: {
    name: "Escola Demo BinGo",
  },
  classes: [
    { id: "class-6a", name: "6º Ano A", bins: 180 },
    { id: "class-7b", name: "7º Ano B", bins: 240 },
    { id: "class-1a", name: "1ª Série A", bins: 310 },
  ],
  students: [
    { id: "ana", name: "Ana Silva", classId: "class-6a", bins: 80 },
    { id: "pedro", name: "Pedro Santos", classId: "class-7b", bins: 120 },
    { id: "joao", name: "João Teste", classId: "class-7b", bins: 60 },
    { id: "maria", name: "Maria Oliveira", classId: "class-1a", bins: 150 },
    { id: "lucas", name: "Lucas Costa", classId: "class-6a", bins: 100 },
  ],
  history: [
    {
      id: crypto.randomUUID(),
      studentId: "ana",
      classId: "class-6a",
      size: "SMALL",
      detectedType: "pilha",
      isValid: true,
      points: 10,
      createdAt: new Date().toISOString(),
    },
  ],
};

const sectionTitles = {
  "discard-section": "Simulador de descarte",
  "student-section": "Informações do aluno",
  "ranking-section": "Rankings",
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

function getStudentById(studentId) {
  return state.students.find((student) => student.id === studentId);
}

function getClassById(classId) {
  return state.classes.find((classroom) => classroom.id === classId);
}

function getStudentClass(student) {
  return getClassById(student.classId);
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
}

function renderStudentOptions() {
  const options = state.students
    .map((student) => `<option value="${student.id}">${student.name}</option>`)
    .join("");

  discardStudentSelect.innerHTML = options;
  studentInfoSelect.innerHTML = options;
}

function updateDiscardClass() {
  const student = getStudentById(discardStudentSelect.value);
  discardClassInput.value = getStudentClass(student).name;
}

function getStudentStats(studentId) {
  const events = state.history.filter((event) => event.studentId === studentId);
  const validEvents = events.filter((event) => event.isValid);
  const invalidEvents = events.filter((event) => !event.isValid);
  const totalGenerated = validEvents.reduce((sum, event) => sum + event.points, 0);
  const lastEvent = events.at(-1);

  return {
    validCount: validEvents.length,
    invalidCount: invalidEvents.length,
    totalGenerated,
    lastEvent,
    events,
  };
}

function renderStudentInfo() {
  const student = getStudentById(studentInfoSelect.value);
  const classroom = getStudentClass(student);
  const stats = getStudentStats(student.id);
  const lastDiscard = stats.lastEvent
    ? `${stats.lastEvent.detectedType} (${stats.lastEvent.size}) - ${
        stats.lastEvent.isValid ? `${stats.lastEvent.points} Bins` : "inválido"
      }`
    : "Nenhum descarte simulado";

  studentDetails.innerHTML = `
    <div class="metric"><span>Nome</span><span>${student.name}</span></div>
    <div class="metric"><span>Turma</span><span>${classroom.name}</span></div>
    <div class="metric"><span>Saldo atual</span><span>${student.bins} Bins</span></div>
    <div class="metric"><span>Descartes válidos</span><span>${stats.validCount}</span></div>
    <div class="metric"><span>Descartes inválidos</span><span>${stats.invalidCount}</span></div>
    <div class="metric"><span>Total gerado</span><span>${stats.totalGenerated} Bins</span></div>
    <div class="metric"><span>Último descarte</span><span>${lastDiscard}</span></div>
  `;

  const recentEvents = stats.events.slice(-5).reverse();
  studentHistory.innerHTML = recentEvents.length
    ? recentEvents
        .map(
          (event) => `
            <article class="history-item">
              <strong>${event.detectedType} - ${event.size}</strong>
              <small>${event.isValid ? `${event.points} Bins gerados` : "Item inválido"} · ${formatDate(event.createdAt)}</small>
            </article>
          `,
        )
        .join("")
    : '<div class="empty-state">Nenhum descarte para este aluno.</div>';
}

function renderRankings() {
  const sortedStudents = [...state.students].sort((a, b) => b.bins - a.bins);
  const sortedClasses = [...state.classes].sort((a, b) => b.bins - a.bins);

  studentRanking.innerHTML = sortedStudents
    .map((student, index) => {
      const classroom = getStudentClass(student);
      return `
        <li class="${index < 3 ? "top" : ""}">
          <div class="ranking-row">
            <strong>${student.name}<br><small>${classroom.name}</small></strong>
            <span>${student.bins} Bins</span>
          </div>
        </li>
      `;
    })
    .join("");

  classRanking.innerHTML = sortedClasses
    .map(
      (classroom, index) => `
        <li class="${index < 3 ? "top" : ""}">
          <div class="ranking-row">
            <strong>${classroom.name}</strong>
            <span>${classroom.bins} Bins</span>
          </div>
        </li>
      `,
    )
    .join("");
}

function renderAll() {
  updateDiscardClass();
  renderStudentInfo();
  renderRankings();
}

function handleDiscardSubmit(event) {
  event.preventDefault();

  const student = getStudentById(discardStudentSelect.value);
  const classroom = getStudentClass(student);
  const size = itemSizeSelect.value;
  const detectedType = detectedTypeSelect.value;
  const isValid = itemValiditySelect.value === "valid";
  const points = isValid ? pointsBySize[size] : 0;

  const historyEvent = {
    id: crypto.randomUUID(),
    studentId: student.id,
    classId: classroom.id,
    size,
    detectedType,
    isValid,
    points,
    createdAt: new Date().toISOString(),
  };

  state.history.push(historyEvent);

  if (!isValid) {
    discardMessage.className = "message error";
    discardMessage.innerHTML = `
      <strong>Item inválido. Nenhum Bin foi gerado.</strong>
      <ul>
        <li>Aluno: ${student.name}</li>
        <li>Turma: ${classroom.name}</li>
        <li>Tipo detectado: ${detectedType}</li>
      </ul>
    `;
    renderAll();
    return;
  }

  student.bins += points;
  classroom.bins += points;

  discardMessage.className = "message success";
  discardMessage.innerHTML = `
    <strong>Descarte simulado com sucesso.</strong>
    <ul>
      <li>Aluno: ${student.name}</li>
      <li>Turma: ${classroom.name}</li>
      <li>Tamanho do item: ${size}</li>
      <li>Tipo detectado: ${detectedType}</li>
      <li>Pontos gerados: ${points} Bins</li>
      <li>Novo saldo do aluno: ${student.bins} Bins</li>
      <li>Novo saldo da turma: ${classroom.bins} Bins</li>
    </ul>
  `;

  renderAll();
}

schoolName.textContent = state.school.name;
renderStudentOptions();
renderAll();

navButtons.forEach((button) => {
  button.addEventListener("click", () => setActiveSection(button.dataset.section));
});

discardStudentSelect.addEventListener("change", updateDiscardClass);
studentInfoSelect.addEventListener("change", renderStudentInfo);
discardForm.addEventListener("submit", handleDiscardSubmit);
