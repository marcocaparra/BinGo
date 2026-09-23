import { FormEvent, useEffect, useMemo, useState } from "react";
import { apiClient } from "../api/client";
import { evaluationResults } from "../data/mockData";
import type { ClassificationCategoryResponse, EvaluationResponse, EvaluationResult } from "../api/client";

interface EvaluationFormProps {
  providerRunId: string;
  providerName: string;
  suggestedClass?: ClassificationCategoryResponse | null;
  onSaved?: (evaluation: EvaluationResponse) => void;
}

function categoryLabel(category: ClassificationCategoryResponse) {
  return `${category.code} - ${category.name}`;
}

function matchesCategoryInput(category: ClassificationCategoryResponse, value: string) {
  const normalizedValue = value.trim().toLowerCase();
  return (
    category.id === value ||
    category.code.toLowerCase() === normalizedValue ||
    category.name.toLowerCase() === normalizedValue ||
    categoryLabel(category).toLowerCase() === normalizedValue
  );
}

export function EvaluationForm({ providerRunId, providerName, suggestedClass, onSaved }: EvaluationFormProps) {
  const [status, setStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const [categories, setCategories] = useState<ClassificationCategoryResponse[]>([]);
  const [classInput, setClassInput] = useState(suggestedClass ? categoryLabel(suggestedClass) : "");
  const [isLoadingCategories, setIsLoadingCategories] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let ignore = false;

    async function loadCategories() {
      setIsLoadingCategories(true);

      try {
        const loadedCategories = await apiClient.listClassificationCategories();

        if (!ignore) {
          setCategories(loadedCategories);
          if (suggestedClass) {
            setClassInput(categoryLabel(suggestedClass));
          }
        }
      } catch (caughtError) {
        if (!ignore) {
          setError(caughtError instanceof Error ? caughtError.message : "Nao foi possivel carregar classes.");
        }
      } finally {
        if (!ignore) {
          setIsLoadingCategories(false);
        }
      }
    }

    loadCategories();

    return () => {
      ignore = true;
    };
  }, [suggestedClass]);

  const selectedCategory = useMemo(
    () => categories.find((category) => matchesCategoryInput(category, classInput)) ?? null,
    [categories, classInput]
  );
  const canCreateCategory = classInput.trim().length > 0 && !selectedCategory;

  async function ensureCategory() {
    if (selectedCategory) {
      return selectedCategory;
    }

    if (!classInput.trim()) {
      throw new Error("Informe a classe correta do objeto.");
    }

    const createdCategory = await apiClient.createClassificationCategory(classInput.trim());
    setCategories((current) => [...current, createdCategory].sort((a, b) => a.displayOrder - b.displayOrder || a.name.localeCompare(b.name)));
    setClassInput(categoryLabel(createdCategory));
    return createdCategory;
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("saving");
    setError(null);

    const formData = new FormData(event.currentTarget);

    try {
      const category = await ensureCategory();
      const evaluation = await apiClient.saveEvaluation(providerRunId, {
        correctClassId: category.id,
        evaluationResult: String(formData.get("evaluationResult")) as EvaluationResult,
        targetObject: formData.get("targetObject") === "yes",
        humanNote: String(formData.get("humanNote") ?? "")
      });

      setStatus("saved");
      onSaved?.(evaluation);
      window.setTimeout(() => setStatus("idle"), 2200);
    } catch (caughtError) {
      setStatus("error");
      setError(caughtError instanceof Error ? caughtError.message : "Nao foi possivel salvar a avaliacao.");
    }
  }

  async function handleCreateCategory() {
    setStatus("saving");
    setError(null);

    try {
      await ensureCategory();
      setStatus("idle");
    } catch (caughtError) {
      setStatus("error");
      setError(caughtError instanceof Error ? caughtError.message : "Nao foi possivel criar a classe.");
    }
  }

  return (
    <form className="evaluation-form" onSubmit={handleSubmit}>
      <div className="form-title-row">
        <h3>Avaliacao humana</h3>
        <span>{providerName}</span>
      </div>

      {suggestedClass ? (
        <div className="suggested-class-panel">
          <span>Classe sugerida pelo provider</span>
          <strong>{categoryLabel(suggestedClass)}</strong>
        </div>
      ) : null}

      <label>
        Objeto real
        <input
          list={`classification-categories-${providerRunId}`}
          name="correctClass"
          onChange={(event) => setClassInput(event.target.value)}
          placeholder={isLoadingCategories ? "Carregando classes..." : "Digite para pesquisar ou criar uma classe"}
          type="text"
          value={classInput}
        />
        <datalist id={`classification-categories-${providerRunId}`}>
          {categories.map((category) => (
            <option key={category.id} value={categoryLabel(category)} />
          ))}
        </datalist>
      </label>

      {canCreateCategory ? (
        <button className="button button-inline" disabled={status === "saving"} onClick={handleCreateCategory} type="button">
          Criar classe "{classInput.trim()}"
        </button>
      ) : null}

      <label>
        Resultado da avaliacao
        <select name="evaluationResult">
          {evaluationResults.map((item) => (
            <option key={item} value={item}>
              {item}
            </option>
          ))}
        </select>
      </label>

      <fieldset>
        <legend>E objeto-alvo do projeto?</legend>
        <div className="segmented-control">
          <label>
            <input defaultChecked name="targetObject" type="radio" value="yes" />
            <span>Sim</span>
          </label>
          <label>
            <input name="targetObject" type="radio" value="no" />
            <span>Nao</span>
          </label>
        </div>
      </fieldset>

      <label>
        Observacao humana
        <textarea
          name="humanNote"
          placeholder="Ex.: API identificou o objeto, mas confundiu o tipo principal."
          rows={4}
        />
      </label>

      {error ? <p className="form-message error">{error}</p> : null}

      <button className={`button button-secondary ${status === "saved" ? "is-saved" : ""}`} disabled={status === "saving"} type="submit">
        {status === "saving" ? "Salvando..." : status === "saved" ? "Avaliacao salva" : "Salvar avaliacao"}
      </button>
    </form>
  );
}
