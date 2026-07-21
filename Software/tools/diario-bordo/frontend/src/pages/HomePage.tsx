import { useEffect, useState } from 'react'
import { getMembers } from '../api/membersApi'
import { getReports } from '../api/reportsApi'

const shortcuts = [
  {
    eyebrow: 'Registrar',
    title: 'Relatório de hoje',
    description: 'Conte o que você fez, as decisões tomadas e o próximo passo.',
    href: '#/hoje',
    action: 'Preencher agora',
  },
  {
    eyebrow: 'Consultar',
    title: 'Histórico coletivo',
    description: 'Acompanhe os registros do grupo por integrante, área e status.',
    href: '#/historico',
    action: 'Ver histórico',
  },
  {
    eyebrow: 'Organizar',
    title: 'Relatórios pendentes',
    description: 'Veja rapidamente quais registros do grupo ainda precisam de atenção.',
    href: '#/pendentes',
    action: 'Ver pendências',
  },
]

function getTodayDate() {
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    timeZone: 'America/Sao_Paulo',
  }).format(new Date())
}

export function HomePage() {
  const [memberCount, setMemberCount] = useState(0)
  const [todayReportCount, setTodayReportCount] = useState(0)
  const [isLoading, setIsLoading] = useState(true)
  const [summaryError, setSummaryError] = useState('')

  useEffect(() => {
    let isCurrent = true

    Promise.all([getMembers(), getReports()])
      .then(([members, reports]) => {
        if (isCurrent) {
          const today = getTodayDate()
          setMemberCount(members.length)
          setTodayReportCount(
            reports.filter((report) => report.reportDate === today).length,
          )
          setSummaryError('')
        }
      })
      .catch((error: unknown) => {
        if (isCurrent) {
          setSummaryError(
            error instanceof Error
              ? error.message
              : 'Não foi possível carregar o resumo.',
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

  const pendingCount = Math.max(memberCount - todayReportCount, 0)
  const progress = memberCount > 0
    ? Math.round((todayReportCount / memberCount) * 100)
    : 0
  const reportLabel = todayReportCount === 1 ? 'relatório enviado' : 'relatórios enviados'

  return (
    <div className="page home-page">
      <section className="hero-section">
        <div className="hero-copy">
          <span className="eyebrow"><span className="live-dot" /> Projeto BinGo</span>
          <h1>Diário de Bordo<br />BinGo</h1>
          <p>
            Um lugar simples para registrar o que o grupo construiu hoje e
            manter a evolução do projeto sempre visível.
          </p>
          <div className="hero-actions">
            <a className="button primary" href="#/hoje">Criar relatório</a>
            <a className="button secondary" href="#/historico">Explorar histórico</a>
          </div>
        </div>

        <aside className="today-panel" aria-label="Resumo do dia">
          <div className="today-panel-header">
            <span>Resumo de hoje</span>
            <span className="soft-badge">API</span>
          </div>
          <div className="today-stat">
            <strong>{isLoading || summaryError ? '—' : todayReportCount}</strong>
            <span>{isLoading ? 'carregando dados' : reportLabel}</span>
          </div>
          <div className="progress-track" aria-label={`${progress}% dos relatórios enviados`}>
            <span style={{ width: `${progress}%` }} />
          </div>
          <div className="today-footer">
            <span>{isLoading || summaryError ? '— integrantes' : `${memberCount} integrantes`}</span>
            <span>{isLoading || summaryError ? '— pendentes' : `${pendingCount} pendentes`}</span>
          </div>
          {summaryError && <p className="today-panel-error">{summaryError}</p>}
        </aside>
      </section>

      <section className="shortcut-section">
        <div className="section-heading">
          <div>
            <span className="eyebrow">Acesso rápido</span>
            <h2>O que você precisa fazer?</h2>
          </div>
          <p>Escolha um caminho para continuar.</p>
        </div>

        <div className="shortcut-grid">
          {shortcuts.map((shortcut, index) => (
            <a className="shortcut-card" href={shortcut.href} key={shortcut.title}>
              <span className="shortcut-number">0{index + 1}</span>
              <span className="eyebrow">{shortcut.eyebrow}</span>
              <h3>{shortcut.title}</h3>
              <p>{shortcut.description}</p>
              <span className="text-link">{shortcut.action} <span aria-hidden="true">→</span></span>
            </a>
          ))}
        </div>
      </section>
    </div>
  )
}
