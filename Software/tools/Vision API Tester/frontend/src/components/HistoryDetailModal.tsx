import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { apiClient } from "../api/client";
import type {
  ClassificationCategoryResponse,
  HistoryItemResponse,
  HistoryProviderResponse,
  ImageValidationResponse
} from "../api/client";
import { ImageValidationForm } from "./ImageValidationForm";
import { ProviderResultCard } from "./ProviderResultCard";

interface HistoryDetailModalProps {
  imageId: string;
  categories: ClassificationCategoryResponse[];
  onClose: () => void;
  onValidationSaved: (validation: ImageValidationResponse) => void;
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "long",
    timeStyle: "short"
  }).format(new Date(value));
}

function matchesProvider(provider: HistoryProviderResponse, name: "aws" | "google") {
  const normalizedName = provider.provider.toLowerCase();
  return name === "aws"
    ? normalizedName.includes("aws") || normalizedName.includes("rekognition")
    : normalizedName.includes("google") || normalizedName.includes("cloud vision");
}

function sortNewestFirst(results: HistoryProviderResponse[]) {
  return [...results].sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt));
}

function ProviderPanel({
  title,
  results
}: {
  title: string;
  results: HistoryProviderResponse[];
}) {
  return (
    <section className="history-provider-panel" aria-label={title}>
      <div className="history-provider-panel-title">
        <div>
          <span>Provider</span>
          <h3>{title}</h3>
        </div>
        <span className="status-pill status-muted">
          {results.length === 1 ? "1 execução" : `${results.length} execuções`}
        </span>
      </div>

      {results.length > 0 ? (
        <div className="history-provider-runs">
          {results.map((result) => (
            <ProviderResultCard
              key={result.providerRunId}
              result={{
                providerName: result.provider,
                responseTimeMs: result.responseTimeMs,
                labels: result.labels,
                suggestedClass: result.suggestedClass,
                classificationStatus: result.classificationStatus,
                classificationScore: result.classificationScore,
                classificationMargin: result.classificationMargin,
                classificationEngineVersion: result.classificationEngineVersion,
                classificationEvidence: result.classificationEvidence,
                ewasteEligibility: result.ewasteEligibility,
                eligibilityCorrect: result.eligibilityCorrect,
                classificationCorrect: result.classificationCorrect,
                rawResponse: result.rawResponse,
                status: result.status
              }}
            />
          ))}
        </div>
      ) : (
        <div className="empty-state compact">
          <strong>Nenhuma execução encontrada</strong>
          <span>Este registro não possui resultado salvo para {title}.</span>
        </div>
      )}
    </section>
  );
}

export function HistoryDetailModal({
  imageId,
  categories,
  onClose,
  onValidationSaved
}: HistoryDetailModalProps) {
  const [detail, setDetail] = useState<HistoryItemResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [loadAttempt, setLoadAttempt] = useState(0);
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  const requestClose = useCallback(() => {
    if (!isSaving) {
      onClose();
    }
  }, [isSaving, onClose]);

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();

    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, []);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        requestClose();
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [requestClose]);

  useEffect(() => {
    let ignore = false;
    setIsLoading(true);
    setLoadError(null);
    setDetail(null);

    apiClient.getHistoryItem(imageId)
      .then((loadedDetail) => {
        if (!ignore) {
          setDetail(loadedDetail);
        }
      })
      .catch((caughtError) => {
        if (!ignore) {
          setLoadError(
            caughtError instanceof Error ? caughtError.message : "Não foi possível carregar os detalhes da imagem."
          );
        }
      })
      .finally(() => {
        if (!ignore) {
          setIsLoading(false);
        }
      });

    return () => {
      ignore = true;
    };
  }, [imageId, loadAttempt]);

  const providerGroups = useMemo(() => {
    const providerResults = detail?.providerResults ?? [];
    const aws = sortNewestFirst(providerResults.filter((provider) => matchesProvider(provider, "aws")));
    const google = sortNewestFirst(providerResults.filter((provider) => matchesProvider(provider, "google")));
    const knownRunIds = new Set([...aws, ...google].map((provider) => provider.providerRunId));
    const other = sortNewestFirst(
      providerResults.filter((provider) => !knownRunIds.has(provider.providerRunId))
    );
    return { aws, google, other };
  }, [detail]);

  function handleValidationSaved(validation: ImageValidationResponse) {
    const correctnessByRunId = new Map(
      validation.providerResults.map((result) => [result.providerRunId, result])
    );

    setDetail((currentDetail) => currentDetail
      ? {
          ...currentDetail,
          imageValidation: validation,
          providerResults: currentDetail.providerResults.map((provider) => {
            const correctness = correctnessByRunId.get(provider.providerRunId);
            return correctness
              ? {
                  ...provider,
                  eligibilityCorrect: correctness.eligibilityCorrect,
                  classificationCorrect: correctness.classificationCorrect
                }
              : provider;
          })
        }
      : currentDetail);
    onValidationSaved(validation);
  }

  return (
    <div
      className="modal-overlay"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) {
          requestClose();
        }
      }}
      role="presentation"
    >
      <div
        aria-busy={isLoading || isSaving}
        aria-labelledby="history-detail-title"
        aria-modal="true"
        className="history-modal"
        role="dialog"
      >
        <header className="history-modal-header">
          <div>
            <span className="eyebrow">Detalhes da imagem</span>
            <h2 id="history-detail-title">{detail?.imageName ?? "Carregando registro..."}</h2>
            {detail ? (
              <p>
                {detail.projectName} · {formatDate(detail.uploadedAt)} · {detail.imageId}
              </p>
            ) : null}
          </div>
          <button
            aria-label={isSaving ? "Aguarde o salvamento para fechar" : "Fechar detalhes"}
            className="modal-close-button"
            disabled={isSaving}
            onClick={requestClose}
            ref={closeButtonRef}
            type="button"
          >
            Fechar
          </button>
        </header>

        <div className="history-modal-body">
          {isLoading ? (
            <div className="modal-state" role="status">
              <span className="loading-indicator" aria-hidden="true" />
              <strong>Carregando detalhes</strong>
              <span>Buscando o registro completo da imagem.</span>
            </div>
          ) : loadError ? (
            <div className="modal-state warning" role="alert">
              <strong>Não foi possível carregar os detalhes</strong>
              <span>{loadError}</span>
              <button
                className="button button-inline"
                onClick={() => setLoadAttempt((currentAttempt) => currentAttempt + 1)}
                type="button"
              >
                Tentar novamente
              </button>
            </div>
          ) : detail ? (
            <>
              <ImageValidationForm
                categories={categories}
                imageId={detail.imageId}
                initialValidation={detail.imageValidation}
                onSaved={handleValidationSaved}
                onSavingChange={setIsSaving}
              />

              <div className="history-provider-grid">
                <ProviderPanel results={providerGroups.aws} title="AWS Rekognition" />
                <ProviderPanel results={providerGroups.google} title="Google Cloud Vision" />
              </div>

              {providerGroups.other.length > 0 ? (
                <div className="history-other-providers">
                  <ProviderPanel results={providerGroups.other} title="Outros providers" />
                </div>
              ) : null}
            </>
          ) : null}
        </div>
      </div>
    </div>
  );
}
