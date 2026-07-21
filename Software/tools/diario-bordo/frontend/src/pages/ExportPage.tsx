import { useEffect, useMemo, useState } from 'react'
import {
  downloadDailyReport,
  getPendingReports,
  getReports,
} from '../api/reportsApi'
import type { Member } from '../types/member'
import type { DailyReport } from '../types/report'

function todayIsoDate() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
}

export function ExportPage() {
  const [selectedDate, setSelectedDate] = useState(todayIsoDate)
  const [reports, setReports] = useState<DailyReport[]>([])
  const [pendingMembers, setPendingMembers] = useState<Member[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [isDownloading, setIsDownloading] = useState(false)
  const [error, setError] = useState('')
  const [downloadMessage, setDownloadMessage] = useState('')

  useEffect(() => {
    let isCurrent = true

    Promise.all([
      getReports(selectedDate),
      getPendingReports(selectedDate),
    ])
      .then(([reportsData, pendingData]) => {
        if (isCurrent) {
          setReports(reportsData)
          setPendingMembers(pendingData)
        }
      })
      .catch((requestError: unknown) => {
        if (isCurrent) {
          setError(
            requestError instanceof Error
              ? requestError.message
              : 'Não foi possível carregar o painel.',
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
  }, [selectedDate])

  const activityReports = useMemo(
    () => reports.filter((report) => report.status !== 'NO_ACTIVITY'),
    [reports],
  )
  const selectedDateIsToday = selectedDate === todayIsoDate()

  async function handleDownload() {
    setIsDownloading(true)
    setDownloadMessage('')
    setError('')

    try {
      const markdown = await downloadDailyReport(selectedDate)
      const blob = new Blob([markdown], { type: 'text/markdown;charset=utf-8' })
      const url = URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      link.download = `diario-bordo-${selectedDate}.md`
      document.body.appendChild(link)
      link.click()
      link.remove()
      URL.revokeObjectURL(url)
      setDownloadMessage('Relatório Markdown gerado.')
    } catch (requestError: unknown) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : 'Não foi possível baixar o relatório.',
      )
    } finally {
      setIsDownloading(false)
    }
  }

  return (
    <div className="page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Painel de coordenação</span>
          <h1>Consolidado do dia</h1>
          <p>Escolha uma data para ver quem respondeu, quem ainda falta e baixar o Markdown.</p>
        </div>
        <div className="date-chip">
          <span>Data do relatório</span>
          <label className="date-input-shell">
            <input
              aria-label="Data do relatório"
              type="date"
              value={selectedDate}
              max={todayIsoDate()}
              onChange={(event) => {
                const nextDate = event.target.value > todayIsoDate() ? todayIsoDate() : event.target.value
                setSelectedDate(nextDate)
                setIsLoading(true)
                setError('')
                setDownloadMessage('')
              }}
            />
            <span className="date-input-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24">
                <path d="M7 9l5 5 5-5" />
              </svg>
            </span>
          </label>
          <em className={`today-label ${selectedDateIsToday ? '' : 'is-hidden'}`}>Hoje</em>
        </div>
      </header>

      {error && <div className="feedback-message error page-feedback">{error}</div>}
      {downloadMessage && <div className="feedback-message page-feedback">{downloadMessage}</div>}

      <section className="admin-summary compact-summary" aria-live="polite">
        <div className="count-box">
          <strong>{isLoading ? '—' : activityReports.length}</strong>
          <span>respostas recebidas</span>
        </div>
        <div className="count-box attention">
          <strong>{isLoading ? '—' : pendingMembers.length}</strong>
          <span>pendentes</span>
        </div>
        <button
          className="button primary"
          type="button"
          disabled={isLoading || isDownloading}
          onClick={handleDownload}
        >
          {isDownloading ? 'Gerando...' : 'Baixar relatório do dia'}
        </button>
      </section>

      <section className="admin-columns two-admin-columns">
        <div className="admin-list">
          <h2>Respostas recebidas</h2>
          {isLoading ? (
            <p>Carregando...</p>
          ) : activityReports.length === 0 ? (
            <p>Nenhuma resposta recebida para esta data.</p>
          ) : (
            activityReports.map((report) => (
              <article className="admin-row" key={report.id}>
                <strong>{report.memberName}</strong>
                <span>{report.area}</span>
                <p>{report.title}</p>
              </article>
            ))
          )}
        </div>

        <div className="admin-list">
          <h2>Pendentes</h2>
          {isLoading ? (
            <p>Carregando...</p>
          ) : pendingMembers.length === 0 ? (
            <p>Nenhum integrante pendente.</p>
          ) : (
            pendingMembers.map((member) => (
              <article className="admin-row compact" key={member.id}>
                <strong>{member.name}</strong>
                <span>{member.defaultArea ?? 'Área não informada'}</span>
              </article>
            ))
          )}
        </div>
      </section>
    </div>
  )
}
