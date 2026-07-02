import { useState } from 'react'

export function ExportPage() {
  const [showNotice, setShowNotice] = useState(false)

  return (
    <div className="page export-page">
      <section className="export-card">
        <div className="export-visual" aria-hidden="true">
          <span className="sheet-tab">XLSX</span>
          <div className="sheet-grid">
            {Array.from({ length: 20 }).map((_, index) => <span key={index} />)}
          </div>
        </div>
        <div className="export-copy">
          <span className="eyebrow">Funcionalidade futura</span>
          <h1>Exportar diário</h1>
          <p>
            Em uma próxima versão, os registros poderão ser organizados e
            baixados em uma planilha <code>.xlsx</code> pronta para consulta.
          </p>
          <ul className="feature-list">
            <li>Filtros por período e integrante</li>
            <li>Uma linha por relatório enviado</li>
            <li>Links de evidência incluídos</li>
          </ul>
          <button className="button primary" type="button" onClick={() => setShowNotice(true)}>
            Baixar planilha
          </button>
          {showNotice && (
            <p className="inline-notice" role="status">
              A exportação ainda não está disponível nesta V0.
            </p>
          )}
        </div>
      </section>
    </div>
  )
}
