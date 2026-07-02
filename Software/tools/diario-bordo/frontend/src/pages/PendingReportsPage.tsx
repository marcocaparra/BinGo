import { useState } from 'react'
import { mockPendingReports } from '../data/mockData'

function formatDate(date: string) {
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${date}T12:00:00Z`))
}

export function PendingReportsPage() {
  const [feedback, setFeedback] = useState('')

  return (
    <div className="page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Acompanhamento</span>
          <h1>Relatórios pendentes</h1>
          <p>Registros que ainda precisam ser preenchidos ou marcados sem atividade.</p>
        </div>
        <div className="count-box attention">
          <strong>{mockPendingReports.length}</strong>
          <span>pendências abertas</span>
        </div>
      </header>

      {feedback && <div className="feedback-message page-feedback" role="status">{feedback}</div>}

      <section className="pending-list">
        {mockPendingReports.map((report) => (
          <article className="pending-item" key={report.id}>
            <div className="member-avatar" aria-hidden="true">
              {report.memberName.split(' ').map((part) => part[0]).slice(0, 2).join('')}
            </div>
            <div className="pending-person">
              <h2>{report.memberName}</h2>
              <p>{report.area}</p>
            </div>
            <div className="pending-date">
              <span>Data pendente</span>
              <strong>{formatDate(report.reportDate)}</strong>
            </div>
            <span className="status-badge status-pending">Pendente</span>
            <div className="pending-actions">
              <a className="button small primary" href="#/hoje">Preencher agora</a>
              <button
                className="button small secondary"
                type="button"
                onClick={() => setFeedback(`Ação simulada para ${report.memberName}. Nenhum dado foi alterado.`)}
              >
                Marcar sem atividade
              </button>
            </div>
          </article>
        ))}
      </section>
    </div>
  )
}
