import type {
  CreateNoActivityReportRequest,
  CreateTodayReportRequest,
  DailyReport,
  ReportExistence,
  UpdateDailyReportRequest,
} from '../types/report'
import type { Member } from '../types/member'
import { request, requestText, requestVoid } from './httpClient'

export function getReports(date?: string): Promise<DailyReport[]> {
  const query = date ? `?date=${encodeURIComponent(date)}` : ''
  return request<DailyReport[]>(`/reports${query}`)
}

export function getPendingReports(date: string): Promise<Member[]> {
  return request<Member[]>(`/reports/pending?date=${encodeURIComponent(date)}`)
}

export function downloadDailyReport(date: string): Promise<string> {
  return requestText(`/reports/export?date=${encodeURIComponent(date)}`)
}

export function checkReportExists(memberId: string, date: string): Promise<ReportExistence> {
  const query = new URLSearchParams({ memberId, date })
  return request<ReportExistence>(`/reports/exists?${query.toString()}`)
}

export function createTodayReport(
  payload: CreateTodayReportRequest,
  files: File[] = [],
): Promise<DailyReport> {
  if (files.length > 0) {
    const formData = new FormData()
    formData.append(
      'report',
      new Blob([JSON.stringify(payload)], { type: 'application/json' }),
    )
    files.forEach((file) => formData.append('files', file))

    return request<DailyReport>('/reports/today', {
      method: 'POST',
      body: formData,
    })
  }

  return request<DailyReport>('/reports/today', {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}

export function createNoActivityReport(
  payload: CreateNoActivityReportRequest,
): Promise<DailyReport> {
  return request<DailyReport>('/reports/no-activity', {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}

export function updateReport(
  reportId: string,
  payload: UpdateDailyReportRequest,
): Promise<DailyReport> {
  return request<DailyReport>(`/reports/${reportId}`, {
    method: 'PUT',
    body: JSON.stringify(payload),
  })
}

export function uploadReportAttachments(
  reportId: string,
  files: File[],
): Promise<DailyReport> {
  const formData = new FormData()
  files.forEach((file) => formData.append('files', file))

  return request<DailyReport>(`/reports/${reportId}/attachments`, {
    method: 'POST',
    body: formData,
  })
}

export function deleteReport(reportId: string): Promise<void> {
  return requestVoid(`/reports/${reportId}`, {
    method: 'DELETE',
  })
}
