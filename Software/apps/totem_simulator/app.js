const API_BASE_URL = "http://localhost:8000/v1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";

// Chave exposta apenas porque este Ã© um simulador web de desenvolvimento.
// No totem real, a API key deve ficar protegida no serviço local do Edge/Orange Pi.
const MACHINE_API_KEY = "edge-demo-key";
const VISION_ENDPOINT = new URLSearchParams(window.location.search).get("visionUrl")
  || "http://127.0.0.1:8765/vision/analyze";
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const SUPPORTED_IMAGE_TYPES = new Set(["image/jpeg", "image/png"]);
const visionProvider = BinGoVision.createVisionProvider({ remoteUrl: VISION_ENDPOINT });

const visionItemConfig = {
  battery: { detectedType: "pilha", category: "BATTERY", label: "Pilha ou bateria" },
  cable: { detectedType: "cabo", category: "CABLE_WIRE", label: "Cabo, fio ou carregador" },
  phone: { detectedType: "celular", category: "MOBILE_DEVICE", label: "Celular ou smartphone" },
  small: { detectedType: "eletrônico pequeno", category: "PERIPHERAL", label: "Eletrônico pequeno" },
};

const visionOriginLabels = {
  AWS_REKOGNITION: "AWS Rekognition",
  GEMINI_FALLBACK: "Gemini (confirmação)",
  MANUAL_REVIEW: "Revisão necessária",
};

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
    imageFile: null,
    imageObjectUrl: null,
    analysis: null,
    busy: false,
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
const itemImageInput = document.querySelector("#item-image-input");
const itemImageDropzone = document.querySelector("#item-image-dropzone");
const itemImagePreview = document.querySelector("#item-image-preview");
const itemImagePreviewImage = document.querySelector("#item-image-preview-image");
const itemImageName = document.querySelector("#item-image-name");
const itemImageMeta = document.querySelector("#item-image-meta");
const sampleGrid = document.querySelector("#sample-grid");
const sampleFilters = document.querySelectorAll("[data-sample-filter]");
const sampleFiles = new Map();
const visionAnalysis = document.querySelector("#vision-analysis");
const visionAnalysisTitle = document.querySelector("#vision-analysis-title");
const visionAnalysisCopy = document.querySelector("#vision-analysis-copy");
const visionResult = document.querySelector("#vision-result");
const visionResultBadge = document.querySelector("#vision-result-badge");
const visionResultItem = document.querySelector("#vision-result-item");
const visionResultCategory = document.querySelector("#vision-result-category");
const visionResultConfidence = document.querySelector("#vision-result-confidence");
const visionResultOrigin = document.querySelector("#vision-result-origin");
const analyzeItemButton = document.querySelector("#analyze-item-button");
const retryItemButton = document.querySelector("#retry-item-button");
const confirmDiscardButton = document.querySelector("#confirm-discard-button");
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
  state.discard.busy = !isEnabled;
  discardFlow.querySelectorAll("button, input, select").forEach((element) => {
    element.disabled = !isEnabled;
  });
  if (isEnabled) {
    updateVisionControls();
  }
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

function formatFileSize(bytes) {
  if (bytes < 1024 * 1024) {
    return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  }
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function setVisionStatus(kind, title, copy) {
  visionAnalysis.className = `vision-analysis ${kind}`;
  visionAnalysisTitle.textContent = title;
  visionAnalysisCopy.textContent = copy;
}

function updateVisionControls() {
  const hasImage = Boolean(state.discard.imageFile);
  const hasAnalysis = Boolean(state.discard.analysis);
  analyzeItemButton.hidden = hasAnalysis;
  analyzeItemButton.disabled = state.discard.busy || !hasImage;
  retryItemButton.hidden = !hasAnalysis;
  retryItemButton.disabled = state.discard.busy;
  confirmDiscardButton.hidden = !hasAnalysis;
  confirmDiscardButton.disabled = state.discard.busy;
}

function resetVisionInput() {
  if (state.discard.imageObjectUrl) {
    URL.revokeObjectURL(state.discard.imageObjectUrl);
  }
  state.discard.imageFile = null;
  state.discard.imageObjectUrl = null;
  state.discard.analysis = null;
  itemImageInput.value = "";
  itemImageDropzone.hidden = false;
  itemImagePreview.hidden = true;
  itemImagePreviewImage.removeAttribute("src");
  visionResult.hidden = true;
  setVisionStatus("idle", "Aguardando imagem", "A análise ainda não foi iniciada.");
  updateVisionControls();
}

function selectVisionFile(file) {
  if (!file) {
    return;
  }
  if (!SUPPORTED_IMAGE_TYPES.has(file.type)) {
    setVisionStatus("error", "Formato não aceito", "Escolha uma imagem PNG ou JPG.");
    return;
  }
  if (file.size > MAX_IMAGE_BYTES) {
    setVisionStatus("error", "Imagem muito grande", "Escolha um arquivo de até 5 MB.");
    return;
  }

  if (state.discard.imageObjectUrl) {
    URL.revokeObjectURL(state.discard.imageObjectUrl);
  }
  state.discard.imageFile = file;
  state.discard.imageObjectUrl = URL.createObjectURL(file);
  state.discard.analysis = null;
  itemImageInput.value = "";
  itemImagePreviewImage.src = state.discard.imageObjectUrl;
  itemImageName.textContent = file.name || "Imagem selecionada";
  itemImageMeta.textContent = `${file.type === "image/png" ? "PNG" : "JPG"} · ${formatFileSize(file.size)}`;
  itemImageDropzone.hidden = true;
  itemImagePreview.hidden = false;
  visionResult.hidden = true;
  setVisionStatus("ready", "Imagem pronta", "Confira a prévia e inicie a análise.");
  updateVisionControls();
}

function renderSampleLibrary(filter = "all") {
  sampleGrid.replaceChildren();
  for (const sample of BinGoSamples) {
    if (filter !== "all" && sample.level !== filter) continue;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "sample-card";
    button.draggable = true;
    button.dataset.sampleId = sample.id;
    button.disabled = state.discard.busy;
    button.setAttribute("aria-label", `Usar ${sample.title}. ${sample.level}. ${sample.note}`);
    const image = document.createElement("img");
    image.src = `assets/samples/${sample.file}`;
    image.alt = "";
    image.loading = "lazy";
    image.draggable = false;
    const title = document.createElement("strong");
    title.textContent = sample.title;
    const level = document.createElement("span");
    level.className = "sample-level";
    level.textContent = sample.level;
    const note = document.createElement("small");
    note.textContent = sample.note;
    button.append(image, title, level, note);
    sampleGrid.append(button);
  }
}

async function selectSample(id) {
  if (state.discard.busy) return;
  const sample = BinGoSamples.find((entry) => entry.id === id);
  if (!sample) return;
  setDiscardEnabled(false);
  try {
    let file = sampleFiles.get(id);
    if (!file) {
      const response = await fetch(`assets/samples/${sample.file}`);
      if (!response.ok) throw new Error("Sample unavailable");
      const blob = await response.blob();
      file = new File([blob], sample.file, { type: "image/png" });
      sampleFiles.set(id, file);
    }
    selectVisionFile(file);
    itemImagePreview.scrollIntoView({ block: "nearest" });
  } catch {
    setVisionStatus("error", "Imagem indisponível", "Tente outra imagem do acervo ou escolha um arquivo do computador.");
  } finally {
    setDiscardEnabled(true);
  }
}

function mapVisionResult(result) {
  const config = result.status === BinGoVision.VisionResult.RECOGNIZED
    ? visionItemConfig[result.itemId]
    : null;
  const isValid = Boolean(config);
  return {
    status: result.status,
    itemId: result.itemId,
    label: config?.label || "Item não autorizado",
    detectedType: config?.detectedType || "objeto inválido",
    category: config?.category || "UNKNOWN",
    categoryLabel: config?.label || "Não identificada",
    categorySource: isValid ? "AI_CONFIRMED" : "UNIDENTIFIED",
    confidence: result.confidence,
    origin: result.origin,
    isValid,
  };
}

function renderVisionResult(analysis) {
  visionResult.className = `vision-result ${analysis.isValid ? "accepted" : "rejected"}`;
  visionResult.hidden = false;
  visionResultBadge.className = `vision-result-badge ${analysis.isValid ? "accepted" : "rejected"}`;
  visionResultBadge.textContent = analysis.isValid ? "Aceito para demonstração" : "Não autorizado";
  visionResultItem.textContent = analysis.label;
  visionResultCategory.textContent = analysis.categoryLabel;
  visionResultConfidence.textContent = Number.isFinite(analysis.confidence)
    ? `${Math.round(analysis.confidence * 100)}%`
    : "Não informada";
  visionResultOrigin.textContent = visionOriginLabels[analysis.origin] || analysis.origin || "Serviço de visão";
  setVisionStatus(
    analysis.isValid ? "success" : "warning",
    analysis.isValid ? "Item reconhecido" : "Item deve ser devolvido",
    analysis.isValid
      ? "A decisão da IA está pronta para compor o registro do descarte."
      : "A imagem foi analisada, mas o item não foi confirmado como eletrônico autorizado.",
  );
  updateVisionControls();
}

async function analyzeSelectedItem() {
  if (!state.discard.imageFile || state.discard.busy) {
    return;
  }

  try {
    setDiscardEnabled(false);
    analyzeItemButton.textContent = "Analisando...";
    setVisionStatus("loading", "Analisando imagem", "Primeira leitura com AWS Rekognition.");
    const frame = { blob: state.discard.imageFile };
    let result = await visionProvider.analyze({
      frame,
      stage: BinGoVision.VisionStage.PRIMARY,
    });

    if (result.status === BinGoVision.VisionResult.NEEDS_SECONDARY) {
      setVisionStatus("loading", "Confirmando resultado", "A primeira leitura ficou incerta. Consultando o Gemini.");
      result = await visionProvider.analyze({
        frame,
        stage: BinGoVision.VisionStage.SECONDARY,
      });
    }

    state.discard.analysis = mapVisionResult(result);
    renderVisionResult(state.discard.analysis);
  } catch (error) {
    state.discard.analysis = null;
    visionResult.hidden = true;
    setVisionStatus(
      "error",
      "Não foi possível analisar",
      "Confira se o serviço de visão está ligado e tente novamente com uma imagem nítida.",
    );
    setDiscardMessage(
      "<strong>Falha controlada na análise.</strong><p>O item não foi registrado. Ajuste a imagem ou confira o serviço de visão antes de tentar novamente.</p>",
      "message error",
    );
  } finally {
    analyzeItemButton.textContent = "Analisar item";
    setDiscardEnabled(true);
  }
}

function retryVisionCapture() {
  resetVisionInput();
  itemImageInput.click();
}

function resetDiscardFlow({ keepMessage = false } = {}) {
  resetVisionInput();
  state.discard = {
    screen: "start",
    mode: null,
    classId: state.context?.classes[0]?.id || null,
    studentId: null,
    pin: "",
    studentToken: null,
    imageFile: null,
    imageObjectUrl: null,
    analysis: null,
    busy: false,
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
  resetVisionInput();
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
  const analysis = state.discard.analysis;
  if (!analysis) {
    throw new Error("Analise a imagem antes de registrar o resultado.");
  }
  return {
    event_id: crypto.randomUUID(),
    student_id: state.discard.mode === "identified" ? state.discard.studentId : null,
    class_id: classId,
    is_valid: analysis.isValid,
    detected_type: analysis.detectedType,
    waste_category_code: analysis.isValid ? analysis.category : null,
    category_source: analysis.isValid ? analysis.categorySource : null,
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
    <div class="metric"><span>Categoria</span><span>${deposit.waste_category_code || "sem categoria"}</span></div>
    <div class="metric"><span>Aluno</span><span>${refreshedStudent ? refreshedStudent.name : "Sem identificação"}</span></div>
    <div class="metric"><span>XP da turma</span><span>${deposit.points_awarded_class} XP</span></div>
    <div class="metric"><span>XP acumulado</span><span>${refreshedClass ? `${refreshedClass.points_class_balance} XP` : "-"}</span></div>
  `;

  if (refreshedStudent) {
    discardResultCard.innerHTML += `
      <div class="metric"><span>BinCoins do aluno</span><span>${deposit.points_awarded_student}</span></div>
      <div class="metric"><span>Bônus ambiental</span><span>${deposit.bonus_bincoins_awarded}</span></div>
      <div class="metric"><span>Saldo do aluno</span><span>${refreshedStudent.points_student_balance} BinCoins</span></div>
    `;
  }

  setDiscardMessage(
    `<strong>${validText}.</strong><p>${refreshedStudent ? `Aluno: ${refreshedStudent.name}. ` : "Sem aluno identificado. "}Turma: ${refreshedClass?.name || "-"}.</p>`,
    `message ${statusClass}`,
  );
}

async function confirmDiscard() {
  if (!state.discard.analysis) {
    setDiscardMessage("<strong>Analise uma imagem antes de continuar.</strong>", "message error");
    return;
  }

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
    "analyze-item": analyzeSelectedItem,
    "retry-item": retryVisionCapture,
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
    ? `${lastDeposit.detected_type || "sem tipo"} (${lastDeposit.waste_category_code || "sem categoria"}) - ${
        lastDeposit.is_valid ? `${lastDeposit.points_awarded_student} BinCoins` : "inválido"
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
              <strong>${deposit.detected_type || "sem tipo"} - ${deposit.waste_category_code || "sem categoria"}</strong>
              <small>${deposit.is_valid ? `${deposit.points_awarded_student} BinCoins (${deposit.bonus_bincoins_awarded} de bônus)` : "Item inválido"} - ${formatDate(deposit.created_at)}</small>
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

itemImageDropzone.addEventListener("click", () => {
  if (!state.discard.busy) {
    itemImageInput.click();
  }
});

itemImageInput.addEventListener("change", () => {
  selectVisionFile(itemImageInput.files?.[0]);
});

["dragenter", "dragover"].forEach((eventName) => {
  itemImageDropzone.addEventListener(eventName, (event) => {
    event.preventDefault();
    if (!state.discard.busy) {
      itemImageDropzone.classList.add("dragging");
    }
  });
});

["dragleave", "drop"].forEach((eventName) => {
  itemImageDropzone.addEventListener(eventName, (event) => {
    event.preventDefault();
    itemImageDropzone.classList.remove("dragging");
  });
});

function receiveImageDrop(event) {
  event.preventDefault();
  if (state.discard.busy) return;
  const sampleId = event.dataTransfer?.getData("application/x-bingo-sample");
  if (sampleId) selectSample(sampleId);
  else selectVisionFile(event.dataTransfer?.files?.[0]);
}

itemImageDropzone.addEventListener("drop", receiveImageDrop);
itemImagePreview.addEventListener("dragover", (event) => event.preventDefault());
itemImagePreview.addEventListener("drop", receiveImageDrop);
sampleGrid.addEventListener("click", (event) => {
  const card = event.target.closest("[data-sample-id]");
  if (card) selectSample(card.dataset.sampleId);
});
sampleGrid.addEventListener("dragstart", (event) => {
  const card = event.target.closest("[data-sample-id]");
  if (!card || state.discard.busy) { event.preventDefault(); return; }
  event.dataTransfer.setData("application/x-bingo-sample", card.dataset.sampleId);
  event.dataTransfer.effectAllowed = "copy";
});
sampleFilters.forEach((button) => button.addEventListener("click", () => {
  sampleFilters.forEach((entry) => entry.setAttribute("aria-pressed", String(entry === button)));
  renderSampleLibrary(button.dataset.sampleFilter);
}));
renderSampleLibrary();

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
