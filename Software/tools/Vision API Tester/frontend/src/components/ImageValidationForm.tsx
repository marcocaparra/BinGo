import { FormEvent, useEffect, useMemo, useState } from "react";
import { apiClient } from "../api/client";
import type { ClassificationCategoryResponse, ImageValidationResponse } from "../api/client";

interface ImageValidationFormProps {
  imageId: string;
  initialValidation?: ImageValidationResponse | null;
  categories?: ClassificationCategoryResponse[];
  onSaved: (validation: ImageValidationResponse) => void;
  onSavingChange?: (isSaving: boolean) => void;
}

type TruthChoice = "YES" | "NO" | "INVALID";

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

function initialChoice(validation?: ImageValidationResponse | null): TruthChoice {
  if (validation?.imageValidationStatus === "INVALID") {
    return "INVALID";
  }

  return validation?.humanIsEwaste === false ? "NO" : "YES";
}

export function ImageValidationForm({
  imageId,
  initialValidation,
  categories: providedCategories,
  onSaved,
  onSavingChange
}: ImageValidationFormProps) {
  const [choice, setChoice] = useState<TruthChoice>(() => initialChoice(initialValidation));
  const [categories, setCategories] = useState<ClassificationCategoryResponse[]>(() =>
    (providedCategories ?? []).filter((category) => category.categoryType === "SPECIFIC")
  );
  const [classInput, setClassInput] = useState(() =>
    initialValidation?.humanConfirmedClass ? categoryLabel(initialValidation.humanConfirmedClass) : ""
  );
  const [humanNote, setHumanNote] = useState(initialValidation?.humanNote ?? "");
  const [status, setStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (providedCategories) {
      setCategories(providedCategories.filter((category) => category.categoryType === "SPECIFIC"));
      return;
    }

    let ignore = false;
    apiClient.listClassificationCategories()
      .then((loadedCategories) => {
        if (!ignore) {
          setCategories(loadedCategories.filter((category) => category.categoryType === "SPECIFIC"));
        }
      })
      .catch((caughtError) => {
        if (!ignore) {
          setError(caughtError instanceof Error ? caughtError.message : "Não foi possível carregar as classes.");
        }
      });
    return () => {
      ignore = true;
    };
  }, [providedCategories]);

  const selectedCategory = useMemo(
    () => categories.find((category) => matchesCategoryInput(category, classInput)) ?? null,
    [categories, classInput]
  );

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    if (choice === "YES" && classInput.trim() && !selectedCategory) {
      setStatus("error");
      setError("Selecione uma classe existente no catálogo.");
      return;
    }

    setStatus("saving");
    onSavingChange?.(true);

    try {
      const validation = await apiClient.saveImageValidation(imageId, {
        imageValidationStatus: choice === "INVALID" ? "INVALID" : "VALID",
        humanIsEwaste: choice === "INVALID" ? null : choice === "YES",
        humanConfirmedClassId: choice === "YES" ? selectedCategory?.id ?? null : null,
        humanNote
      });
      setStatus("saved");
      onSaved(validation);
    } catch (caughtError) {
      setStatus("error");
      setError(caughtError instanceof Error ? caughtError.message : "Não foi possível salvar a validação.");
    } finally {
      onSavingChange?.(false);
    }
  }

  return (
    <form className="evaluation-form image-validation-form" onSubmit={handleSubmit}>
      <div className="form-title-row">
        <div>
          <h3>Validação humana da imagem</h3>
          <span>Uma única verdade de referência para todos os providers</span>
        </div>
      </div>

      <fieldset disabled={status === "saving"}>
        <legend>Este objeto é e-lixo?</legend>
        <div className="segmented-control validation-choice">
          {([
            ["YES", "Sim"],
            ["NO", "Não"],
            ["INVALID", "Imagem inválida"]
          ] as const).map(([value, label]) => (
            <label key={value}>
              <input
                checked={choice === value}
                name="truthChoice"
                onChange={() => {
                  setChoice(value);
                  setStatus("idle");
                  if (value !== "YES") {
                    setClassInput("");
                  }
                }}
                type="radio"
                value={value}
              />
              <span>{label}</span>
            </label>
          ))}
        </div>
      </fieldset>

      {choice === "YES" ? (
        <label>
          Classe correta <small>(opcional)</small>
          <input
            disabled={status === "saving"}
            list={`image-validation-categories-${imageId}`}
            onChange={(event) => {
              setClassInput(event.target.value);
              setStatus("idle");
            }}
            placeholder="Digite para pesquisar no catálogo"
            type="text"
            value={classInput}
          />
          <datalist id={`image-validation-categories-${imageId}`}>
            {categories.map((category) => (
              <option key={category.id} value={categoryLabel(category)} />
            ))}
          </datalist>
        </label>
      ) : null}

      <label>
        Descrição ou observação <small>(opcional)</small>
        <textarea
          disabled={status === "saving"}
          onChange={(event) => {
            setHumanNote(event.target.value);
            setStatus("idle");
          }}
          placeholder="Contexto opcional sobre a validação."
          rows={3}
          value={humanNote}
        />
      </label>

      <div aria-live="polite">
        {error ? <p className="form-message error">{error}</p> : null}
        {status === "saved" ? (
          <p className="form-message success">Validação salva e Histórico atualizado.</p>
        ) : null}
      </div>

      <button className="button button-secondary" disabled={status === "saving"} type="submit">
        {status === "saving" ? "Salvando..." : initialValidation ? "Salvar alterações" : "Salvar validação"}
      </button>
    </form>
  );
}
