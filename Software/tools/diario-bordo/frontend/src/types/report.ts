export type ReportStatus =
  | 'SUBMITTED'
  | 'SUBMITTED_LATE'
  | 'NO_ACTIVITY'

export type DailyReport = {
  id: string
  memberId: string
  memberName: string
  reportDate: string
  area: string
  title: string
  description: string
  problems?: string | null
  solution?: string | null
  nextSteps?: string | null
  evidenceLinks?: string | null
  timeSpentMinutes?: number | null
  status: ReportStatus
  submittedAt: string
  createdAt?: string
  updatedAt?: string
}

export type CreateTodayReportRequest = {
  memberId: string
  area: string
  title: string
  description: string
  problems?: string
  solution?: string
  nextSteps?: string
  evidenceLinks?: string
  timeSpentMinutes?: number
}

export type CreateNoActivityReportRequest = {
  memberId: string
}
