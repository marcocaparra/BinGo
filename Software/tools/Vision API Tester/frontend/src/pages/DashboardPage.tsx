import { useEffect, useMemo, useState } from "react";
import { apiClient } from "../api/client";
import type {
  ClassProviderPerformanceResponse,
  DashboardMetricsResponse,
  ProviderComparisonResponse
} from "../api/client";
import { DashboardSection } from "../components/DashboardSection";
import { MetricCard, type Metric } from "../components/MetricCard";

function ProgressBar({ value }: { value: number }) {
  const normalizedValue = Math.max(0, Math.min(value, 100));

  return (
    <div aria-label={`${normalizedValue.toFixed(1)}%`} className="progress-track">
      <span style={{ width: `${normalizedValue}%` }} />
    </div>
  );
}

function formatPercent(value: number) {
  return `${value.toFixed(1)}%`;
}

function formatMs(value: number) {
  return value <= 0 ? "0 ms" : `${Math.round(value)} ms`;
}

function bestProvider(providers: ProviderComparisonResponse[]) {
  return providers[0] ?? null;
}

function latencyPosition(provider: ProviderComparisonResponse, providers: ProviderComparisonResponse[]) {
  const maxLatency = Math.max(...providers.map((item) => item.p95ResponseTimeMs), 1);
  return Math.max(4, (provider.p95ResponseTimeMs / maxLatency) * 100);
}

function accuracyPosition(provider: ProviderComparisonResponse) {
  return Math.max(4, provider.eligibilityAccuracyRate);
}

function classRowsByName(rows: ClassProviderPerformanceResponse[]) {
  return Array.from(new Set(rows.map((row) => row.expectedClass))).sort();
}

function alertClass(severity: string) {
  if (severity === "success") {
    return "status-success";
  }
  if (severity === "warning") {
    return "status-warning";
  }
  return "status-muted";
}

export function DashboardPage() {
  const [metrics, setMetrics] = useState<DashboardMetricsResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let ignore = false;

    async function loadDashboard() {
      setIsLoading(true);
      setError(null);

      try {
        const dashboardMetrics = await apiClient.getDashboard();
        if (!ignore) {
          setMetrics(dashboardMetrics);
        }
      } catch (caughtError) {
        if (!ignore) {
          setError(caughtError instanceof Error ? caughtError.message : "Não foi possível carregar o dashboard.");
        }
      } finally {
        if (!ignore) {
          setIsLoading(false);
        }
      }
    }

    loadDashboard();
    return () => {
      ignore = true;
    };
  }, []);

  const metricCards = useMemo<Metric[]>(() => {
    if (!metrics) {
      return [];
    }

    const leader = bestProvider(metrics.providerComparisons);
    return [
      {
        label: "Provider líder",
        value: leader?.provider ?? "-",
        helper: leader
          ? `${formatPercent(leader.eligibilityAccuracyRate)} em detecção de e-lixo`
          : "Sem execuções avaliadas"
      },
      {
        label: "Execuções avaliadas",
        value: String(metrics.completedEvaluations),
        helper: `${metrics.pendingEvaluations} pendentes de ${metrics.totalProviderRuns}`
      },
      {
        label: "Acurácia de e-lixo",
        value: formatPercent(metrics.eligibilityAccuracyRate),
        helper: `${metrics.eligibilityCorrectRuns} de ${metrics.eligibilityEvaluatedRuns}, sem REVIEW`
      },
      {
        label: "Precisão / Recall",
        value: `${formatPercent(metrics.precisionRate)} / ${formatPercent(metrics.recallRate)}`,
        helper: `${metrics.falsePositives} FP · ${metrics.falseNegatives} FN`
      },
      {
        label: "Acurácia da classe",
        value: formatPercent(metrics.classificationAccuracyRate),
        helper: `${metrics.classificationCorrectRuns} de ${metrics.classificationEvaluatedRuns}`
      },
      {
        label: "Cobertura",
        value: formatPercent(metrics.sampleQuality.evaluationCoverageRate),
        helper: `${metrics.reviewRuns} REVIEW · ${formatPercent(metrics.reviewRate)} das execuções`
      }
    ];
  }, [metrics]);

  const classNames = useMemo(() => classRowsByName(metrics?.classPerformance ?? []), [metrics]);
  const providers = metrics?.providerComparisons.map((provider) => provider.provider) ?? [];

  return (
    <>
      <div className="page-heading">
        <div>
          <span className="eyebrow">Dashboard</span>
          <h1>Comparação técnica de APIs de visão</h1>
          <p>
            Detecção de e-lixo, classificação específica e latência calculadas a partir da validação humana da
            imagem e dos resultados persistidos de cada provider.
          </p>
        </div>
        <span className={`status-pill ${error ? "status-warning" : "status-ready"}`}>
          {error ? "Backend indisponível" : "Dados reais"}
        </span>
      </div>

      {isLoading ? (
        <div className="empty-state">
          <strong>Carregando dashboard</strong>
          <span>Buscando métricas técnicas em /api/dashboard.</span>
        </div>
      ) : error ? (
        <div className="empty-state warning">
          <strong>Não foi possível carregar os dados reais</strong>
          <span>{error}</span>
        </div>
      ) : metrics ? (
        <>
          <section className="metric-grid" aria-label="Métricas principais">
            {metricCards.map((metric) => (
              <MetricCard key={metric.label} metric={metric} />
            ))}
          </section>

          <DashboardSection
            action={<span className="status-pill status-muted">{metrics.alerts.length} alertas</span>}
            description="Sinais derivados de cobertura, tamanho da amostra, validações pendentes e taxa de REVIEW."
            title="Confiança da leitura"
          >
            <div className="alert-grid">
              {metrics.alerts.map((alert) => (
                <article
                  className={`dashboard-alert ${alertClass(alert.severity)}`}
                  key={`${alert.title}-${alert.message}`}
                >
                  <strong>{alert.title}</strong>
                  <span>{alert.message}</span>
                </article>
              ))}
            </div>
          </DashboardSection>

          <DashboardSection
            description="REVIEW é contabilizado separadamente e não entra como acerto ou erro binário. A classe só é avaliada quando existe classe humana confirmada."
            title="Detecção de e-lixo e classificação específica"
          >
            {metrics.decisionMetrics.length > 0 ? (
              <div className="table-shell">
                <table>
                  <thead>
                    <tr>
                      <th>Provider</th>
                      <th>Acurácia e-lixo</th>
                      <th>Precisão</th>
                      <th>Recall</th>
                      <th>FP / FN</th>
                      <th>REVIEW</th>
                      <th>Acurácia da classe</th>
                      <th>Classificação específica</th>
                    </tr>
                  </thead>
                  <tbody>
                    {metrics.decisionMetrics.map((provider) => (
                      <tr key={provider.provider}>
                        <td>
                          <strong>{provider.provider}</strong>
                          <span>{provider.validatedRuns} execuções com verdade válida</span>
                        </td>
                        <td>
                          {formatPercent(provider.eligibilityAccuracyRate)}
                          <span>{provider.eligibilityCorrectRuns} de {provider.eligibilityEvaluatedRuns}</span>
                        </td>
                        <td>{formatPercent(provider.precisionRate)}</td>
                        <td>{formatPercent(provider.recallRate)}</td>
                        <td>{provider.falsePositives} / {provider.falseNegatives}</td>
                        <td>
                          {formatPercent(provider.reviewRate)}
                          <span>{provider.reviewRuns} de {provider.totalRuns}</span>
                        </td>
                        <td>
                          {formatPercent(provider.classificationAccuracyRate)}
                          <span>{provider.classificationCorrectRuns} de {provider.classificationEvaluatedRuns}</span>
                        </td>
                        <td>
                          {formatPercent(provider.specificClassificationRate)}
                          <span>{provider.specificallyClassifiedRuns} classificadas</span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="empty-state">
                <strong>Sem execuções</strong>
                <span>Execute providers e valide imagens para gerar as métricas.</span>
              </div>
            )}
          </DashboardSection>

          <DashboardSection
            description="Ordenação por acurácia de e-lixo, acurácia da classe, macro por classe, menor REVIEW e menor latência."
            title="Ranking de providers"
          >
            {metrics.providerComparisons.length > 0 ? (
              <div className="provider-ranking-grid">
                {metrics.providerComparisons.map((provider, index) => (
                  <article className="provider-rank-card" key={provider.provider}>
                    <div className="rank-header">
                      <span>#{index + 1}</span>
                      <h3>{provider.provider}</h3>
                    </div>
                    <strong>{formatPercent(provider.eligibilityAccuracyRate)}</strong>
                    <ProgressBar value={provider.eligibilityAccuracyRate} />
                    <dl className="metric-list provider-metric-list">
                      <div>
                        <dt>Classe</dt>
                        <dd>{formatPercent(provider.classificationAccuracyRate)}</dd>
                      </div>
                      <div>
                        <dt>Macro classe</dt>
                        <dd>{formatPercent(provider.macroClassificationAccuracyRate)}</dd>
                      </div>
                      <div>
                        <dt>Avaliadas</dt>
                        <dd>{provider.evaluatedRuns}</dd>
                      </div>
                      <div>
                        <dt>P95</dt>
                        <dd>{formatMs(provider.p95ResponseTimeMs)}</dd>
                      </div>
                    </dl>
                    <div className="result-split">
                      <span className="status-success">
                        {provider.eligibilityCorrectRuns} detecções corretas
                      </span>
                      <span className="status-warning">
                        {provider.eligibilityIncorrectRuns} detecções incorretas
                      </span>
                      <span className="status-muted">{provider.reviewRuns} REVIEW</span>
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhum provider disponível</strong>
                <span>Execute providers para gerar o ranking.</span>
              </div>
            )}
          </DashboardSection>

          <DashboardSection
            description="Cada ponto compara acurácia de detecção contra a cauda de latência. Quanto mais alto e mais à esquerda, melhor."
            title="Acurácia de e-lixo × latência"
          >
            {metrics.providerComparisons.length > 0 ? (
              <div className="accuracy-latency-panel">
                <div className="scatter-plane" aria-label="Gráfico de acurácia por latência">
                  {metrics.providerComparisons.map((provider) => (
                    <div
                      className="scatter-point"
                      key={provider.provider}
                      style={{
                        left: `${latencyPosition(provider, metrics.providerComparisons)}%`,
                        bottom: `${accuracyPosition(provider)}%`
                      }}
                    >
                      <span>{provider.provider}</span>
                    </div>
                  ))}
                </div>
                <div className="table-shell">
                  <table>
                    <thead>
                      <tr>
                        <th>Provider</th>
                        <th>Acurácia e-lixo</th>
                        <th>Acurácia da classe</th>
                        <th>Macro classe</th>
                        <th>Média</th>
                        <th>Mediana</th>
                        <th>P95</th>
                        <th>Cobertura</th>
                      </tr>
                    </thead>
                    <tbody>
                      {metrics.providerComparisons.map((provider) => (
                        <tr key={provider.provider}>
                          <td>
                            <strong>{provider.provider}</strong>
                            <span>{provider.runs} execuções totais</span>
                          </td>
                          <td>{formatPercent(provider.eligibilityAccuracyRate)}</td>
                          <td>{formatPercent(provider.classificationAccuracyRate)}</td>
                          <td>{formatPercent(provider.macroClassificationAccuracyRate)}</td>
                          <td>{formatMs(provider.averageResponseTimeMs)}</td>
                          <td>{formatMs(provider.medianResponseTimeMs)}</td>
                          <td>{formatMs(provider.p95ResponseTimeMs)}</td>
                          <td>{formatPercent(provider.sampleCoverageRate)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : (
              <div className="empty-state">
                <strong>Sem pontos para comparar</strong>
                <span>A comparação precisa de pelo menos uma execução.</span>
              </div>
            )}
          </DashboardSection>

          <DashboardSection
            description="Compara somente a classe humana confirmada; falhas de elegibilidade não são misturadas nesta matriz."
            title="Desempenho por classe humana"
          >
            {metrics.classPerformance.length > 0 ? (
              <div className="class-matrix">
                {classNames.map((className) => (
                  <article className="class-row-card" key={className}>
                    <div className="class-row-title">
                      <span className="class-badge">{className}</span>
                    </div>
                    <div className="class-provider-grid">
                      {providers.map((providerName) => {
                        const row = metrics.classPerformance.find(
                          (item) => item.expectedClass === className && item.provider === providerName
                        );

                        return row ? (
                          <div className="class-provider-cell" key={`${className}-${providerName}`}>
                            <strong>{providerName}</strong>
                            <div className="inline-progress">
                              <ProgressBar value={row.classificationAccuracyRate} />
                              <span>{formatPercent(row.classificationAccuracyRate)}</span>
                            </div>
                            <small>
                              {row.correctRuns} corretas · {row.wrongClassRuns} classe errada ·{" "}
                              {row.unclassifiedRuns} sem classe
                            </small>
                            <small>
                              {row.evaluatedRuns} avaliadas · específica {formatPercent(row.specificClassificationRate)}
                              {" · "}{formatMs(row.averageResponseTimeMs)}
                            </small>
                          </div>
                        ) : (
                          <div className="class-provider-cell is-empty" key={`${className}-${providerName}`}>
                            <strong>{providerName}</strong>
                            <span>Sem amostra</span>
                          </div>
                        );
                      })}
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhuma classe humana confirmada</strong>
                <span>Confirme classes nas validações para popular a matriz.</span>
              </div>
            )}
          </DashboardSection>

          <div className="two-column">
            <DashboardSection
              description="Lista somente erros de classificação em imagens com classe humana confirmada."
              title="Erros por classe"
            >
              {metrics.classErrors.length > 0 ? (
                <div className="error-list">
                  {metrics.classErrors.slice(0, 8).map((errorItem) => (
                    <article className="error-card" key={`${errorItem.expectedClass}-${errorItem.provider}`}>
                      <div className="card-title-row">
                        <h3>{errorItem.expectedClass}</h3>
                        <span>{errorItem.provider}</span>
                      </div>
                      <strong>{errorItem.totalIncorrectRuns} classificações incorretas</strong>
                      <small>
                        {errorItem.wrongClassRuns} classe errada · {errorItem.unclassifiedRuns} sem classe específica
                      </small>
                      <div className="stacked-tags">
                        {errorItem.topReturnedLabels.length > 0 ? (
                          errorItem.topReturnedLabels.map((label) => (
                            <span key={label.label}>
                              {label.label} · {label.count}x · {formatPercent(label.averageConfidence)}
                            </span>
                          ))
                        ) : (
                          <span>Sem labels armazenadas</span>
                        )}
                      </div>
                    </article>
                  ))}
                </div>
              ) : (
                <div className="empty-state">
                  <strong>Nenhum erro de classificação</strong>
                  <span>Erros de elegibilidade permanecem apenas nas métricas de detecção.</span>
                </div>
              )}
            </DashboardSection>

            <DashboardSection
              description="Cobertura calculada por execução cuja imagem possui validação válida; registros legados entram apenas como fallback."
              title="Tamanho e qualidade da amostra"
            >
              <dl className="sample-quality-list">
                <div>
                  <dt>Imagens</dt>
                  <dd>{metrics.totalImages}</dd>
                </div>
                <div>
                  <dt>Execuções</dt>
                  <dd>{metrics.totalProviderRuns}</dd>
                </div>
                <div>
                  <dt>Avaliadas</dt>
                  <dd>{metrics.sampleQuality.evaluatedRuns}</dd>
                </div>
                <div>
                  <dt>Pendentes</dt>
                  <dd>{metrics.sampleQuality.pendingRuns}</dd>
                </div>
                <div>
                  <dt>Validações válidas</dt>
                  <dd>{metrics.sampleQuality.validImageValidations}</dd>
                </div>
                <div>
                  <dt>Imagens inválidas</dt>
                  <dd>{metrics.sampleQuality.invalidImageValidations}</dd>
                </div>
                <div>
                  <dt>Verdade: e-lixo</dt>
                  <dd>{metrics.sampleQuality.ewasteTruthRuns}</dd>
                </div>
                <div>
                  <dt>Verdade: não e-lixo</dt>
                  <dd>{metrics.sampleQuality.nonEwasteTruthRuns}</dd>
                </div>
                <div>
                  <dt>REVIEW</dt>
                  <dd>{metrics.sampleQuality.reviewRuns}</dd>
                </div>
                <div>
                  <dt>Fallback legado</dt>
                  <dd>{metrics.sampleQuality.legacyFallbackRuns}</dd>
                </div>
              </dl>

              <div className="quality-warning-list">
                <strong>Baixa amostra por provider</strong>
                <span>
                  {metrics.sampleQuality.providersWithLowSample.length > 0
                    ? metrics.sampleQuality.providersWithLowSample.join(", ")
                    : "Nenhum provider abaixo do mínimo."}
                </span>
                <strong>Baixa amostra por classe</strong>
                <span>
                  {metrics.sampleQuality.classesWithLowSample.length > 0
                    ? metrics.sampleQuality.classesWithLowSample.join(", ")
                    : "Nenhuma classe abaixo do mínimo."}
                </span>
              </div>
            </DashboardSection>
          </div>
        </>
      ) : null}
    </>
  );
}
