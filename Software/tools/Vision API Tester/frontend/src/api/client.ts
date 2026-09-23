const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8080/api";

export type ExpectedClass = string;

export type EvaluationResult = "CORRECT" | "PARTIAL" | "WRONG" | "INCONCLUSIVE";

export interface ProjectResponse {
  id: string;
  name: string;
  description: string | null;
  createdAt: string;
}

export interface ImageResponse {
  id: string;
  projectId: string;
  originalFilename: string;
  storedFilename: string;
  storagePath: string;
  contentType: string | null;
  sizeBytes: number;
  checksumSha256: string;
  width: number | null;
  height: number | null;
  createdAt: string;
}

export interface ProviderLabelResponse {
  id: string;
  name: string;
  confidence: number;
}

export interface ClassificationCategoryResponse {
  id: string;
  code: string;
  name: string;
  aliases: string[];
  categoryType: "SPECIFIC" | "GENERIC" | "FALLBACK";
  defaultEwasteEligibility: EwasteEligibility;
  displayOrder: number;
  active: boolean;
}

export type ClassificationStatus = "CLASSIFIED" | "NO_MATCH" | "BELOW_THRESHOLD" | "AMBIGUOUS";
export type EwasteEligibility = "ELIGIBLE" | "NOT_ELIGIBLE" | "REVIEW";
export type ImageValidationStatus = "VALID" | "INVALID";

export interface ClassificationEvidence {
  label: string;
  labelConfidence: number;
  matchedTerm: string;
  matchType: "EXACT" | "PHRASE";
  contribution: number;
}

export interface ProviderResultResponse {
  id: string;
  imageId: string;
  provider: string;
  status: string;
  responseTimeMs: number | null;
  labels: ProviderLabelResponse[];
  suggestedClass: ClassificationCategoryResponse | null;
  classificationStatus: ClassificationStatus | null;
  classificationScore: number | null;
  classificationMargin: number | null;
  classificationEngineVersion: string | null;
  classificationEvidence: ClassificationEvidence[];
  ewasteEligibility: EwasteEligibility;
  eligibilityCorrect: boolean | null;
  classificationCorrect: boolean | null;
  rawResponse: unknown;
  createdAt: string;
}

export interface EvaluationResponse {
  id: string;
  providerRunId: string;
  correctClassId: string;
  correctClass: ExpectedClass;
  correctClassName: string;
  evaluationResult: EvaluationResult;
  targetObject: boolean;
  humanNote: string | null;
  evaluatedAt: string;
}

export interface HistoryProviderResponse {
  providerRunId: string;
  provider: string;
  status: string;
  responseTimeMs: number | null;
  labels: ProviderLabelResponse[];
  suggestedClass: ClassificationCategoryResponse | null;
  classificationStatus: ClassificationStatus | null;
  classificationScore: number | null;
  classificationMargin: number | null;
  classificationEngineVersion: string | null;
  classificationEvidence: ClassificationEvidence[];
  ewasteEligibility: EwasteEligibility;
  eligibilityCorrect: boolean | null;
  classificationCorrect: boolean | null;
  rawResponse: unknown;
  evaluation: EvaluationResponse | null;
  createdAt: string;
}

export interface HistoryItemResponse {
  imageId: string;
  imageName: string;
  uploadedAt: string;
  projectId: string;
  projectName: string;
  imageValidation: ImageValidationResponse | null;
  providerResults: HistoryProviderResponse[];
}

export interface ProviderValidationResultResponse {
  providerRunId: string;
  provider: string;
  eligibilityCorrect: boolean | null;
  classificationCorrect: boolean | null;
}

export interface ImageValidationResponse {
  id: string;
  imageId: string;
  imageValidationStatus: ImageValidationStatus;
  humanIsEwaste: boolean | null;
  humanConfirmedClass: ClassificationCategoryResponse | null;
  humanNote: string | null;
  validatedAt: string;
  providerResults: ProviderValidationResultResponse[];
}

export interface ProviderSummaryResponse {
  provider: string;
  runs: number;
  averageResponseTimeMs: number;
}

export interface ClassSummaryResponse {
  expectedClass: string;
  evaluations: number;
  correctEvaluations: number;
  accuracyRate: number;
}

export interface DashboardSampleQualityResponse {
  validImageValidations: number;
  invalidImageValidations: number;
  evaluatedRuns: number;
  pendingRuns: number;
  legacyFallbackRuns: number;
  ewasteTruthRuns: number;
  nonEwasteTruthRuns: number;
  reviewRuns: number;
  classificationEvaluatedRuns: number;
  evaluationCoverageRate: number;
  minimumRecommendedEvaluationsPerProvider: number;
  minimumRecommendedEvaluationsPerClass: number;
  providersWithLowSample: string[];
  classesWithLowSample: string[];
}

export interface DashboardAlertResponse {
  severity: "success" | "info" | "warning";
  title: string;
  message: string;
}

export interface ProviderComparisonResponse {
  provider: string;
  runs: number;
  evaluatedRuns: number;
  eligibilityEvaluatedRuns: number;
  eligibilityCorrectRuns: number;
  eligibilityIncorrectRuns: number;
  reviewRuns: number;
  classificationEvaluatedRuns: number;
  classificationCorrectRuns: number;
  eligibilityAccuracyRate: number;
  classificationAccuracyRate: number;
  macroClassificationAccuracyRate: number;
  reviewRate: number;
  sampleCoverageRate: number;
  averageResponseTimeMs: number;
  medianResponseTimeMs: number;
  p95ResponseTimeMs: number;
  minResponseTimeMs: number;
  maxResponseTimeMs: number;
}

export interface ProviderDecisionMetricsResponse {
  provider: string;
  totalRuns: number;
  validatedRuns: number;
  eligibilityEvaluatedRuns: number;
  eligibilityCorrectRuns: number;
  eligibilityAccuracyRate: number;
  precisionRate: number;
  recallRate: number;
  falsePositives: number;
  falseNegatives: number;
  reviewRuns: number;
  reviewRate: number;
  classificationEvaluatedRuns: number;
  classificationCorrectRuns: number;
  classificationAccuracyRate: number;
  specificallyClassifiedRuns: number;
  specificClassificationRate: number;
}

export interface ClassProviderPerformanceResponse {
  expectedClass: string;
  provider: string;
  evaluatedRuns: number;
  correctRuns: number;
  wrongClassRuns: number;
  unclassifiedRuns: number;
  classificationAccuracyRate: number;
  specificClassificationRate: number;
  averageResponseTimeMs: number;
}

export interface LabelFrequencyResponse {
  label: string;
  count: number;
  averageConfidence: number;
}

export interface ClassErrorSummaryResponse {
  expectedClass: string;
  provider: string;
  wrongClassRuns: number;
  unclassifiedRuns: number;
  totalIncorrectRuns: number;
  topReturnedLabels: LabelFrequencyResponse[];
}

export interface DashboardMetricsResponse {
  projectId: string | null;
  totalImages: number;
  totalProviderRuns: number;
  completedEvaluations: number;
  pendingEvaluations: number;
  eligibilityEvaluatedRuns: number;
  eligibilityCorrectRuns: number;
  eligibilityAccuracyRate: number;
  precisionRate: number;
  recallRate: number;
  falsePositives: number;
  falseNegatives: number;
  reviewRuns: number;
  reviewRate: number;
  classificationEvaluatedRuns: number;
  classificationCorrectRuns: number;
  classificationAccuracyRate: number;
  specificallyClassifiedRuns: number;
  specificClassificationRate: number;
  averageResponseTimeMs: number;
  providers: ProviderSummaryResponse[];
  classes: ClassSummaryResponse[];
  sampleQuality: DashboardSampleQualityResponse;
  decisionMetrics: ProviderDecisionMetricsResponse[];
  providerComparisons: ProviderComparisonResponse[];
  classPerformance: ClassProviderPerformanceResponse[];
  classErrors: ClassErrorSummaryResponse[];
  alerts: DashboardAlertResponse[];
}

export interface SaveProviderResultRequest {
  imageId: string;
  provider: string;
  responseTimeMs: number;
  labels: Array<{
    name: string;
    confidence: number;
  }>;
  rawResponse: unknown;
}

export interface AnalyzeImageRequest {
  providers: string[];
}

export interface SaveEvaluationRequest {
  correctClassId: string;
  evaluationResult: EvaluationResult;
  targetObject: boolean;
  humanNote: string;
}

export interface SaveImageValidationRequest {
  imageValidationStatus: ImageValidationStatus;
  humanIsEwaste: boolean | null;
  humanConfirmedClassId: string | null;
  humanNote: string;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: init?.body instanceof FormData ? init.headers : { "Content-Type": "application/json", ...init?.headers },
    ...init
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `Backend retornou HTTP ${response.status}`);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return response.json() as Promise<T>;
}

export const apiClient = {
  listProjects() {
    return request<ProjectResponse[]>("/projects");
  },

  listClassificationCategories(query?: string) {
    const search = query ? `?q=${encodeURIComponent(query)}` : "";
    return request<ClassificationCategoryResponse[]>(`/classification-categories${search}`);
  },

  createClassificationCategory(name: string, code?: string, aliases: string[] = []) {
    return request<ClassificationCategoryResponse>("/classification-categories", {
      method: "POST",
      body: JSON.stringify({ name, code, aliases })
    });
  },

  createProject(name: string, description: string) {
    return request<ProjectResponse>("/projects", {
      method: "POST",
      body: JSON.stringify({ name, description })
    });
  },

  uploadImage(projectId: string, file: File) {
    const formData = new FormData();
    formData.append("projectId", projectId);
    formData.append("file", file);

    return request<ImageResponse>("/images", {
      method: "POST",
      body: formData
    });
  },

  saveProviderResult(payload: SaveProviderResultRequest) {
    return request<ProviderResultResponse>("/provider-results", {
      method: "POST",
      body: JSON.stringify(payload)
    });
  },

  analyzeImage(imageId: string, payload: AnalyzeImageRequest) {
    return request<ProviderResultResponse[]>(`/images/${imageId}/analyze`, {
      method: "POST",
      body: JSON.stringify(payload)
    });
  },

  saveEvaluation(providerRunId: string, payload: SaveEvaluationRequest) {
    return request<EvaluationResponse>(`/provider-results/${providerRunId}/evaluation`, {
      method: "PUT",
      body: JSON.stringify(payload)
    });
  },

  saveImageValidation(imageId: string, payload: SaveImageValidationRequest) {
    return request<ImageValidationResponse>(`/images/${imageId}/validation`, {
      method: "PUT",
      body: JSON.stringify(payload)
    });
  },

  getDashboard(projectId?: string) {
    const query = projectId ? `?projectId=${encodeURIComponent(projectId)}` : "";
    return request<DashboardMetricsResponse>(`/dashboard${query}`);
  },

  getHistory(projectId?: string) {
    const query = projectId ? `?projectId=${encodeURIComponent(projectId)}` : "";
    return request<HistoryItemResponse[]>(`/history${query}`);
  },

  getHistoryItem(imageId: string) {
    return request<HistoryItemResponse>(`/history/${imageId}`);
  },

  deleteImage(imageId: string) {
    return request<void>(`/images/${imageId}`, {
      method: "DELETE"
    });
  }
};
