import type { DailyReport, ReportStatus } from '../types/report'

type HistoryReport = Pick<DailyReport, 'memberName' | 'area' | 'status'>

export type HistoryFilters = {
  member: string
  area: string
  status: ReportStatus | ''
}

export function filterHistoryReports<T extends HistoryReport>(
  reports: T[],
  filters: HistoryFilters,
): T[] {
  return reports.filter((report) =>
    (!filters.member || report.memberName === filters.member) &&
    (!filters.area || report.area === filters.area) &&
    (!filters.status || report.status === filters.status),
  )
}
