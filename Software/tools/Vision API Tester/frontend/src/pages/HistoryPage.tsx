import { useEffect, useMemo, useState } from "react";
import { apiClient } from "../api/client";
import type {
  ClassificationCategoryResponse,
  HistoryItemResponse,
  ImageValidationResponse
} from "../api/client";
import { DashboardSection } from "../components/DashboardSection";
import { HistoryDetailModal } from "../components/HistoryDetailModal";
import { HistoryTable } from "../components/HistoryTable";
import { providers } from "../data/mockData";

const allOption = "Todos";

export function HistoryPage() {
  const [items, setItems] = useState<HistoryItemResponse[]>([]);
  const [providerFilter, setProviderFilter] = useState(allOption);
  const [resultFilter, setResultFilter] = useState(allOption);
  const [classFilter, setClassFilter] = useState(allOption);
  const [categories, setCategories] = useState<ClassificationCategoryResponse[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [deletingImageId, setDeletingImageId] = useState<string | null>(null);
  const [selectedImageId, setSelectedImageId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let ignore = false;

    async function loadHistory() {
      setIsLoading(true);
      setError(null);

      try {
        const [historyItems, loadedCategories] = await Promise.all([
          apiClient.getHistory(),
          apiClient.listClassificationCategories()
        ]);

        if (!ignore) {
          setItems(historyItems);
          setCategories(loadedCategories);
        }
      } catch (caughtError) {
        if (!ignore) {
          setError(caughtError instanceof Error ? caughtError.message : "Nao foi possivel carregar o historico.");
        }
      } finally {
        if (!ignore) {
          setIsLoading(false);
        }
      }
    }

    loadHistory();

    return () => {
      ignore = true;
    };
  }, []);

  const providerOptions = useMemo(() => {
    const fromHistory = items.flatMap((item) => item.providerResults.map((provider) => provider.provider));
    const fromConfig = providers.map((provider) => provider.name);
    return Array.from(new Set([...fromConfig, ...fromHistory]));
  }, [items]);

  const filteredItems = useMemo(() => {
    return items.filter((item) => {
      const matchesProvider =
        providerFilter === allOption || item.providerResults.some((provider) => provider.provider === providerFilter);
      const matchesResult =
        resultFilter === allOption ||
        item.providerResults.some((provider) => (provider.evaluation?.evaluationResult ?? "PENDING") === resultFilter);
      const matchesClass =
        classFilter === allOption ||
        item.providerResults.some((provider) => provider.evaluation?.correctClass === classFilter);

      return matchesProvider && matchesResult && matchesClass;
    });
  }, [classFilter, items, providerFilter, resultFilter]);

  async function handleDeleteImage(imageId: string) {
    const shouldDelete = window.confirm("Excluir esta imagem e todas as analises, labels e avaliacoes associadas?");
    if (!shouldDelete) {
      return;
    }

    setDeletingImageId(imageId);
    setError(null);

    try {
      await apiClient.deleteImage(imageId);
      setItems((currentItems) => currentItems.filter((item) => item.imageId !== imageId));
      if (selectedImageId === imageId) {
        setSelectedImageId(null);
      }
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Nao foi possivel excluir a imagem.");
    } finally {
      setDeletingImageId(null);
    }
  }

  function handleValidationSaved(validation: ImageValidationResponse) {
    const correctnessByRunId = new Map(
      validation.providerResults.map((result) => [result.providerRunId, result])
    );

    setItems((currentItems) => currentItems.map((item) => {
      if (item.imageId !== validation.imageId) {
        return item;
      }

      return {
        ...item,
        imageValidation: validation,
        providerResults: item.providerResults.map((provider) => {
          const correctness = correctnessByRunId.get(provider.providerRunId);
          return correctness
            ? {
                ...provider,
                eligibilityCorrect: correctness.eligibilityCorrect,
                classificationCorrect: correctness.classificationCorrect
              }
            : provider;
        })
      };
    }));
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <span className="eyebrow">Historico</span>
          <h1>Testes realizados</h1>
          <p>Consulte execucoes persistidas no backend e seus status de avaliacao humana.</p>
        </div>
        <span className={`status-pill ${error ? "status-warning" : "status-ready"}`}>
          {error ? "Backend indisponivel" : "Dados reais"}
        </span>
      </div>

      <section className="filters-bar">
        <label>
          Provider
          <select value={providerFilter} onChange={(event) => setProviderFilter(event.target.value)}>
            <option>{allOption}</option>
            {providerOptions.map((provider) => (
              <option key={provider}>{provider}</option>
            ))}
          </select>
        </label>

        <label>
          Resultado
          <select value={resultFilter} onChange={(event) => setResultFilter(event.target.value)}>
            <option>{allOption}</option>
            <option>CORRECT</option>
            <option>PARTIAL</option>
            <option>WRONG</option>
            <option>INCONCLUSIVE</option>
            <option>PENDING</option>
          </select>
        </label>

        <label>
          Classe esperada
          <select value={classFilter} onChange={(event) => setClassFilter(event.target.value)}>
            <option>{allOption}</option>
            {categories.map((category) => (
              <option key={category.id} value={category.code}>
                {category.code} - {category.name}
              </option>
            ))}
          </select>
        </label>
      </section>

      <DashboardSection
        action={<span className="status-pill status-muted">{filteredItems.length} testes</span>}
        description="Filtros aplicados no frontend sobre os registros retornados por /api/history."
        title="Registros persistidos"
      >
        {isLoading ? (
          <div className="empty-state">
            <strong>Carregando historico</strong>
            <span>Buscando registros em /api/history.</span>
          </div>
        ) : error ? (
          <div className="empty-state warning">
            <strong>Nao foi possivel carregar o historico</strong>
            <span>{error}</span>
          </div>
        ) : (
          <HistoryTable
            deletingImageId={deletingImageId}
            items={filteredItems}
            onDeleteImage={handleDeleteImage}
            onViewDetails={setSelectedImageId}
          />
        )}
      </DashboardSection>

      {selectedImageId ? (
        <HistoryDetailModal
          categories={categories}
          imageId={selectedImageId}
          onClose={() => setSelectedImageId(null)}
          onValidationSaved={handleValidationSaved}
        />
      ) : null}
    </>
  );
}
