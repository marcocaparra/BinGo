import { FormEvent, useEffect, useState } from "react";
import { apiClient } from "../api/client";
import type { ImageValidationResponse, ProjectResponse, ProviderResultResponse } from "../api/client";
import { ImageValidationForm } from "../components/ImageValidationForm";
import { ImageUploadPreview } from "../components/ImageUploadPreview";
import { ProviderResultCard, type ProviderResultDisplay } from "../components/ProviderResultCard";
import { providers, type ProviderId } from "../data/mockData";

function toDisplayResult(result: ProviderResultResponse): ProviderResultDisplay {
  return {
    providerName: result.provider,
    responseTimeMs: result.responseTimeMs,
    labels: result.labels.map((label) => ({
      name: label.name,
      confidence: Number(label.confidence)
    })),
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
  };
}

export function NewTestPage() {
  const [projects, setProjects] = useState<ProjectResponse[]>([]);
  const [selectedProjectId, setSelectedProjectId] = useState("");
  const [newProjectName, setNewProjectName] = useState("BinGo Lab");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [selectedProviders, setSelectedProviders] = useState<ProviderId[]>(providers.map((provider) => provider.id));
  const [savedResults, setSavedResults] = useState<ProviderResultResponse[]>([]);
  const [analyzedImageId, setAnalyzedImageId] = useState<string | null>(null);
  const [isLoadingProjects, setIsLoadingProjects] = useState(true);
  const [isCreatingProject, setIsCreatingProject] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let ignore = false;

    async function loadProjects() {
      setIsLoadingProjects(true);

      try {
        const loadedProjects = await apiClient.listProjects();

        if (!ignore) {
          setProjects(loadedProjects);
          setSelectedProjectId((current) => current || loadedProjects[0]?.id || "");
        }
      } catch (caughtError) {
        if (!ignore) {
          setError(caughtError instanceof Error ? caughtError.message : "Não foi possível carregar projetos.");
        }
      } finally {
        if (!ignore) {
          setIsLoadingProjects(false);
        }
      }
    }

    loadProjects();

    return () => {
      ignore = true;
    };
  }, []);

  function toggleProvider(providerId: ProviderId) {
    setSelectedProviders((current) =>
      current.includes(providerId) ? current.filter((id) => id !== providerId) : [...current, providerId]
    );
  }

  async function handleCreateProject(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!newProjectName.trim()) {
      setError("Informe um nome para criar o projeto.");
      return;
    }

    setIsCreatingProject(true);
    setError(null);
    setMessage(null);

    try {
      const project = await apiClient.createProject(newProjectName.trim(), "Projeto criado pelo frontend do Vision API Tester.");
      setProjects((current) => [project, ...current]);
      setSelectedProjectId(project.id);
      setMessage(`Projeto "${project.name}" criado.`);
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Não foi possível criar o projeto.");
    } finally {
      setIsCreatingProject(false);
    }
  }

  async function handleRunTest() {
    setError(null);
    setMessage(null);
    setSavedResults([]);
    setAnalyzedImageId(null);

    if (!selectedProjectId) {
      setError("Crie ou selecione um projeto antes de executar o teste.");
      return;
    }

    if (!selectedFile) {
      setError("Selecione uma imagem antes de executar o teste.");
      return;
    }

    if (selectedProviders.length === 0) {
      setError("Selecione ao menos um provider para executar a análise.");
      return;
    }

    setIsRunning(true);

    try {
      const uploadedImage = await apiClient.uploadImage(selectedProjectId, selectedFile);
      const analyzedResults = await apiClient.analyzeImage(uploadedImage.id, {
        providers: selectedProviders
      });

      setSavedResults(analyzedResults);
      setAnalyzedImageId(uploadedImage.id);
      setMessage(`Imagem "${uploadedImage.originalFilename}" analisada pelo backend com ${analyzedResults.length} provider(s).`);
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Não foi possível executar a análise.");
    } finally {
      setIsRunning(false);
    }
  }

  function handleValidationSaved(validation: ImageValidationResponse) {
    const resultsByRunId = new Map(validation.providerResults.map((result) => [result.providerRunId, result]));
    setSavedResults((current) => current.map((result) => {
      const validationResult = resultsByRunId.get(result.id);
      return validationResult
        ? {
            ...result,
            eligibilityCorrect: validationResult.eligibilityCorrect,
            classificationCorrect: validationResult.classificationCorrect
          }
        : result;
    }));
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <span className="eyebrow">Novo Teste</span>
          <h1>Executar teste de visão computacional</h1>
          <p>Envie uma imagem, acione a análise real e registre a avaliação humana.</p>
        </div>
        <span className="status-pill status-ready">Dados reais</span>
      </div>

      <div className="new-test-layout">
        <section className="workflow-panel">
          <div className="section-header">
            <div>
              <h2>Projeto e imagem</h2>
              <p>O backend exige um projeto para registrar os metadados da imagem.</p>
            </div>
          </div>

          <div className="project-controls">
            <label>
              Projeto
              <select
                disabled={isLoadingProjects || projects.length === 0}
                value={selectedProjectId}
                onChange={(event) => setSelectedProjectId(event.target.value)}
              >
                {projects.length === 0 ? <option value="">Nenhum projeto disponível</option> : null}
                {projects.map((project) => (
                  <option key={project.id} value={project.id}>
                    {project.name}
                  </option>
                ))}
              </select>
            </label>

            <form className="inline-form" onSubmit={handleCreateProject}>
              <label>
                Novo projeto
                <input
                  maxLength={120}
                  onChange={(event) => setNewProjectName(event.target.value)}
                  placeholder="Ex.: Hardware Lab"
                  type="text"
                  value={newProjectName}
                />
              </label>
              <button className="button button-secondary" disabled={isCreatingProject} type="submit">
                {isCreatingProject ? "Criando..." : "Criar projeto"}
              </button>
            </form>
          </div>

          <ImageUploadPreview onFileSelected={setSelectedFile} />
        </section>

        <section className="workflow-panel">
          <div className="section-header">
            <div>
              <h2>Providers</h2>
              <p>Selecione uma ou mais APIs. A resposta simulada será gerada e persistida pelo backend.</p>
            </div>
          </div>

          <div className="provider-selector">
            {providers.map((provider) => (
              <label key={provider.id}>
                <input
                  checked={selectedProviders.includes(provider.id)}
                  onChange={() => toggleProvider(provider.id)}
                  type="checkbox"
                  value={provider.id}
                />
                <span>
                  <strong>{provider.name}</strong>
                  <small>{provider.status}</small>
                </span>
              </label>
            ))}
          </div>

          {message ? <p className="form-message success">{message}</p> : null}
          {error ? <p className="form-message error">{error}</p> : null}

          <button className="button button-primary" disabled={isRunning} onClick={handleRunTest} type="button">
            {isRunning ? "Executando..." : "Executar teste"}
          </button>
        </section>
      </div>

      <section className="results-area">
        {savedResults.length === 0 ? (
          <div className="empty-state">
            <strong>Nenhum resultado salvo nesta sessão</strong>
            <span>Após executar o teste, os provider runs retornados pelo backend aparecerão aqui com formulário de avaliação.</span>
          </div>
        ) : (
          <>
            <div className="section-header">
              <div>
                <h2>Resultados salvos</h2>
                <p>Labels e JSON completo gerados pelo backend e armazenados por provider.</p>
              </div>
              <span className="status-pill status-ready">Persistido</span>
            </div>

            <div className="result-grid">
              {savedResults.map((result) => (
                <div className="result-column" key={result.id}>
                  <ProviderResultCard result={toDisplayResult(result)} />
                </div>
              ))}
            </div>
            {analyzedImageId ? (
              <ImageValidationForm imageId={analyzedImageId} onSaved={handleValidationSaved} />
            ) : null}
          </>
        )}
      </section>
    </>
  );
}
