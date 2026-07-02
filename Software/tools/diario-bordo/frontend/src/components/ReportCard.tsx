import type { DailyReport, ReportStatus } from '../types/report'

const statusLabels: Record<ReportStatus, string> = {
  SUBMITTED: 'Enviado',
  SUBMITTED_LATE: 'Enviado com atraso',
  NO_ACTIVITY: 'Sem atividade',
}

function formatDate(date: string) {
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${date}T12:00:00Z`))
}

type ReportCardProps = {
  report: DailyReport
}

export function ReportCard({ report }: ReportCardProps) {
  return (
    <article className="report-card">
      <div className="report-card-topline">
        <span className="report-date">{formatDate(report.reportDate)}</span>
        <span className={`status-badge status-${report.status.toLowerCase()}`}>
          {statusLabels[report.status]}
        </span>
      </div>
      <h3>{report.title}</h3>
      <p>{report.description}</p>
      <div className="report-meta">
        <span>{report.memberName}</span>
        <span aria-hidden="true">·</span>
        <span>{report.area}</span>
      </div>
    </article>
  )
}
