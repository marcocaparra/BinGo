import { useMemo, useState } from 'react'
import { ReportCard } from '../components/ReportCard'
import { areas, members, mockReports } from '../data/mockData'

export function HistoryPage() {
  const [member, setMember] = useState('')
  const [area, setArea] = useState('')
  const [status, setStatus] = useState('')

  const filteredReports = useMemo(
    () => mockReports.filter((report) =>
      (!member || report.memberName === member) &&
      (!area || report.area === area) &&
      (!status || report.status === status),
    ),
    [member, area, status],
  )

  return (
    <div className="page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Memória do projeto</span>
          <h1>Histórico de relatórios</h1>
          <p>Consulte os registros mockados e acompanhe a evolução coletiva.</p>
        </div>
        <div className="count-box">
          <strong>{filteredReports.length}</strong>
          <span>{filteredReports.length === 1 ? 'registro encontrado' : 'registros encontrados'}</span>
        </div>
      </header>

      <section className="filters" aria-label="Filtros do histórico">
        <label>
          Integrante
          <select value={member} onChange={(event) => setMember(event.target.value)}>
            <option value="">Todos</option>
            {members.map((item) => <option key={item}>{item}</option>)}
          </select>
        </label>
        <label>
          Área
          <select value={area} onChange={(event) => setArea(event.target.value)}>
            <option value="">Todas</option>
            {areas.map((item) => <option key={item}>{item}</option>)}
          </select>
        </label>
        <label>
          Status
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="">Todos</option>
            <option value="SUBMITTED">Enviado</option>
            <option value="SUBMITTED_LATE">Enviado com atraso</option>
            <option value="NO_ACTIVITY">Sem atividade</option>
          </select>
        </label>
        <button className="clear-button" type="button" onClick={() => {
          setMember('')
          setArea('')
          setStatus('')
        }}>
          Limpar filtros
        </button>
      </section>

      <section className="report-grid" aria-live="polite">
        {filteredReports.length > 0 ? (
          filteredReports.map((report) => <ReportCard report={report} key={report.id} />)
        ) : (
          <div className="empty-state">
            <span aria-hidden="true">0</span>
            <h2>Nenhum relatório encontrado</h2>
            <p>Tente remover um dos filtros para ampliar a busca.</p>
          </div>
        )}
      </section>
    </div>
  )
}
