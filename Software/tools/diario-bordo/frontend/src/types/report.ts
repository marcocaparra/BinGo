export type ReportStatus =
  | 'SUBMITTED'
  | 'SUBMITTED_LATE'
  | 'NO_ACTIVITY'
  | 'PENDING'

export type DailyReport = {
  id: string
  memberName: string
  area: string
  reportDate: string
  title: string
  description: string
  status: ReportStatus
  submittedAt?: string
}
