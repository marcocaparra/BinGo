import type {
  ClassificationCategoryResponse,
  ClassificationEvidence,
  ClassificationStatus,
  EwasteEligibility
} from "../api/client";

export interface ProviderResultDisplay {
  providerName: string;
  responseTimeMs: number | null;
  labels: Array<{
    name: string;
    confidence: number;
  }>;
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
  status?: string;
}

interface ProviderResultCardProps {
  result: ProviderResultDisplay;
}

export function ProviderResultCard({ result }: ProviderResultCardProps) {
  const classificationMessage = {
    CLASSIFIED: "Classe sugerida pelo motor",
    NO_MATCH: "Nenhum alias ou nome de classe correspondeu às labels",
    BELOW_THRESHOLD: "Nenhuma classe específica atingiu os critérios",
    AMBIGUOUS: "Duas ou mais classes ficaram próximas demais"
  }[result.classificationStatus ?? "NO_MATCH"];
  const eligibilityMessage = {
    ELIGIBLE: "Elegível como e-lixo",
    NOT_ELIGIBLE: "Não elegível",
    REVIEW: "Requer avaliação"
  }[result.ewasteEligibility];
  const ambiguousEligible = result.classificationStatus === "AMBIGUOUS" && result.ewasteEligibility === "ELIGIBLE";
  const classificationTitle = result.suggestedClass
    ? `${result.suggestedClass.code} - ${result.suggestedClass.name}`
    : ambiguousEligible
      ? "Classe específica inconclusiva"
      : result.classificationStatus === "AMBIGUOUS"
        ? "Classe inconclusiva"
        : classificationMessage;
  const classificationContext = ambiguousEligible
    ? "Duas ou mais classes de e-lixo ficaram próximas"
    : result.classificationStatus === "AMBIGUOUS"
      ? "Duas ou mais classes com elegibilidade diferente ficaram próximas"
      : null;
  const classificationDetails = [
    `status ${result.classificationStatus ?? "não disponível"}`,
    result.classificationScore !== null ? `score ${Number(result.classificationScore).toFixed(1)}` : null,
    result.classificationMargin !== null ? `margem ${Number(result.classificationMargin).toFixed(1)}` : null,
    result.classificationEngineVersion ? `motor ${result.classificationEngineVersion}` : null
  ].filter(Boolean).join(" · ");
  const correctnessLabel = (value: boolean | null) => value === null ? "Não avaliada" : value ? "Correta" : "Incorreta";

  return (
    <article className="provider-result-card">
      <div className="provider-result-header">
        <div>
          <h3>{result.providerName}</h3>
          <span>{result.responseTimeMs ? `${(result.responseTimeMs / 1000).toFixed(2)}s response time` : "Sem tempo medido"}</span>
        </div>
        <span className="status-pill status-ready">{result.status ?? "Persistido"}</span>
      </div>

      <div className={`eligibility-panel eligibility-${result.ewasteEligibility.toLowerCase().replace("_", "-")}`}>
        <span>1. É E-LIXO?</span>
        <strong>{eligibilityMessage}</strong>
        <small>{result.ewasteEligibility}</small>
        <small>Detecção de e-lixo: {correctnessLabel(result.eligibilityCorrect)}</small>
      </div>

      <div className={`suggested-class-panel ${result.suggestedClass ? "" : "is-empty"}`}>
        <span>2. QUAL É O OBJETO?</span>
        <strong>{classificationTitle}</strong>
        {classificationContext ? <small className="classification-context">{classificationContext}</small> : null}
        <small>{classificationDetails}</small>
        <small>Identificação do objeto: {correctnessLabel(result.classificationCorrect)}</small>
      </div>

      {result.classificationEvidence.length > 0 ? (
        <details className="classification-evidence">
          <summary>Evidências da classificação ({result.classificationEngineVersion})</summary>
          <ul className="label-list">
            {result.classificationEvidence.map((evidence) => (
              <li key={`${evidence.label}-${evidence.matchedTerm}`}>
                <span>
                  {evidence.label} → {evidence.matchedTerm} ({evidence.matchType})
                </span>
                <strong>+{Number(evidence.contribution).toFixed(1)}</strong>
              </li>
            ))}
          </ul>
        </details>
      ) : null}

      <ul className="label-list">
        {result.labels.map((label) => (
          <li key={`${result.providerName}-${label.name}`}>
            <span>{label.name}</span>
            <strong>{Number(label.confidence).toFixed(1)}%</strong>
          </li>
        ))}
      </ul>

      <details className="raw-json-panel">
        <summary className="raw-json-header">
          <h4>JSON completo da resposta</h4>
          <span>stored raw_response</span>
        </summary>
        <pre>{JSON.stringify(result.rawResponse, null, 2)}</pre>
      </details>
    </article>
  );
}
