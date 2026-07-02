import { useEffect, useMemo, useState } from 'react'
import { getReports } from '../api/reportsApi'
import { ReportCard } from '../components/ReportCard'
import type { DailyReport, ReportStatus } from '../types/report'

export function HistoryPage() {
  const [reports, setReports] = useState<DailyReport[]>([])
  const [member, setMember] = useState('')
  const [area, setArea] = useState('')
  const [status, setStatus] = useState<ReportStatus | ''>('')
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let isCurrent = true

    getReports()
      .then((data) => {
        if (isCurrent) {
          setReports(data)
          setError('')
        }
      })
      .catch((requestError: unknown) => {
        if (isCurrent) {
          setError(
            requestError instanceof Error
              ? requestError.message
              : 'Não foi possível carregar os relatórios.',
          )
        }
      })
      .finally(() => {
        if (isCurrent) {
          setIsLoading(false)
        }
      })

    return () => {
      isCurrent = false
    }
  }, [])

  const members = useMemo(
    () => [...new Set(reports.map((report) => report.memberName))]
      .sort((first, second) => first.localeCompare(second, 'pt-BR')),
    [reports],
  )

  const areas = useMemo(
    () => [...new Set(reports.map((report) => report.area))]
      .sort((first, second) => first.localeCompare(second, 'pt-BR')),
    [reports],
  )

  const filteredReports = useMemo(
    () => reports.filter((report) =>
      (!member || report.memberName === member) &&
      (!area || report.area === area) &&
      (!status || report.status === status),
    ),
    [reports, member, area, status],
  )

  return (
    <div className="page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Memória do projeto</span>
          <h1>Histórico de relatórios</h1>
          <p>Consulte os registros enviados e acompanhe a evolução coletiva.</p>
        </div>
        <div className="count-box">
          <strong>{isLoading ? '—' : filteredReports.length}</strong>
          <span>{filteredReports.length === 1 ? 'registro encontrado' : 'registros encontrados'}</span>
        </div>
      </header>

      <section className="filters" aria-label="Filtros do histórico">
        <label>
          Integrante
          <select value={member} disabled={isLoading || Boolean(error)} onChange={(event) => setMember(event.target.value)}>
            <option value="">Todos</option>
            {members.map((item) => <option key={item}>{item}</option>)}
          </select>
        </label>
        <label>
          Área
          <select value={area} disabled={isLoading || Boolean(error)} onChange={(event) => setArea(event.target.value)}>
            <option value="">Todas</option>
            {areas.map((item) => <option key={item}>{item}</option>)}
          </select>
        </label>
        <label>
          Status
          <select
            value={status}
            disabled={isLoading || Boolean(error)}
            onChange={(event) => setStatus(event.target.value as ReportStatus | '')}
          >
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
        {isLoading ? (
          <div className="empty-state state-message">
            <h2>Carregando relatórios...</h2>
          </div>
        ) : error ? (
          <div className="empty-state state-message error">
            <h2>Não foi possível carregar os relatórios.</h2>
            <p>{error}</p>
          </div>
        ) : filteredReports.length > 0 ? (
          filteredReports.map((report) => <ReportCard report={report} key={report.id} />)
        ) : (
          <div className="empty-state">
            <span aria-hidden="true">0</span>
            <h2>Nenhum relatório encontrado</h2>
            <p>{reports.length > 0 ? 'Tente remover um dos filtros para ampliar a busca.' : 'Os relatórios enviados aparecerão aqui.'}</p>
          </div>
        )}
      </section>
    </div>
  )
}
