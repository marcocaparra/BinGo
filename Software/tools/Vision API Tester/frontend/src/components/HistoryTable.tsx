import type { HistoryItemResponse } from "../api/client";

interface HistoryTableProps {
  items: HistoryItemResponse[];
  deletingImageId?: string | null;
  onDeleteImage: (imageId: string) => void;
  onViewDetails: (imageId: string) => void;
}

type HistoryStatus = "Avaliado" | "Pendente" | "Inconclusivo";

const statusClasses: Record<HistoryStatus, string> = {
  Avaliado: "status-success",
  Pendente: "status-warning",
  Inconclusivo: "status-muted"
};

function formatDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short"
  }).format(new Date(value));
}

function getStatus(item: HistoryItemResponse): HistoryStatus {
  if (!item.imageValidation) {
    return "Pendente";
  }

  if (item.imageValidation.imageValidationStatus === "INVALID") {
    return "Inconclusivo";
  }

  return "Avaliado";
}

export function HistoryTable({
  items,
  deletingImageId,
  onDeleteImage,
  onViewDetails
}: HistoryTableProps) {
  if (items.length === 0) {
    return (
      <div className="empty-state">
        <strong>Nenhum teste encontrado</strong>
        <span>Execute um novo teste para popular o histórico com dados reais do backend.</span>
      </div>
    );
  }

  return (
    <div className="table-shell">
      <table className="history-table">
        <thead>
          <tr>
            <th>Imagem</th>
            <th>Data</th>
            <th>Projeto</th>
            <th>Verdade humana</th>
            <th>Status</th>
            <th>Ações</th>
          </tr>
        </thead>
        <tbody>
          {items.map((item) => {
            const status = getStatus(item);
            const isDeleting = deletingImageId === item.imageId;

            return (
              <tr key={item.imageId}>
                <td>
                  <strong>{item.imageName}</strong>
                  <span>{item.imageId}</span>
                </td>
                <td>{formatDate(item.uploadedAt)}</td>
                <td>{item.projectName}</td>
                <td>
                  {item.imageValidation ? (
                    <div className="stacked-tags">
                      <span>
                        {item.imageValidation.imageValidationStatus === "INVALID"
                          ? "Imagem inválida"
                          : item.imageValidation.humanIsEwaste
                            ? "É e-lixo"
                            : "Não é e-lixo"}
                      </span>
                      {item.imageValidation.humanConfirmedClass ? (
                        <span className="class-badge">{item.imageValidation.humanConfirmedClass.code}</span>
                      ) : null}
                    </div>
                  ) : (
                    <span className="status-pill status-warning">Pendente</span>
                  )}
                </td>
                <td>
                  <span className={`status-pill ${statusClasses[status]}`}>{status}</span>
                </td>
                <td>
                  <div className="history-actions">
                    <button
                      className="button history-detail-button"
                      disabled={isDeleting}
                      onClick={() => onViewDetails(item.imageId)}
                      type="button"
                    >
                      Ver detalhes
                    </button>
                    <button
                      className="button history-delete-button"
                      disabled={isDeleting}
                      onClick={() => onDeleteImage(item.imageId)}
                      type="button"
                    >
                      {isDeleting ? "Excluindo..." : "Excluir imagem"}
                    </button>
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
