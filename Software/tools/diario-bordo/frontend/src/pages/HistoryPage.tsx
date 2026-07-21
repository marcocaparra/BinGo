import { useEffect, useMemo, useState, type FormEvent, type KeyboardEvent } from 'react'
import { deleteReport, getReports, updateReport } from '../api/reportsApi'
import { API_BASE_URL } from '../config/api'
import type { DailyReport, ReportStatus, UpdateDailyReportRequest } from '../types/report'
import { filterHistoryReports } from './historyFilters'

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

function valueOrEmpty(value?: string | null) {
  return value ?? ''
}

function formatFileSize(sizeBytes: number) {
  if (sizeBytes < 1024 * 1024) {
    return `${Math.max(1, Math.round(sizeBytes / 1024))} KB`
  }
  return `${(sizeBytes / 1024 / 1024).toFixed(1).replace('.', ',')} MB`
}

function attachmentHref(downloadUrl: string) {
  if (/^https?:\/\//i.test(downloadUrl)) {
    return downloadUrl
  }
  return `${API_BASE_URL}${downloadUrl.startsWith('/') ? '' : '/'}${downloadUrl}`
}

function optionalField(formData: FormData, name: string) {
  const value = formData.get(name)?.toString().trim()
  return value || undefined
}

function requiredField(formData: FormData, name: string) {
  return formData.get(name)?.toString().trim() ?? ''
}

function submitOnEnter(event: KeyboardEvent<HTMLFormElement>) {
  if (event.key !== 'Enter' || event.shiftKey || event.nativeEvent.isComposing) {
    return
  }

  if (event.target instanceof HTMLButtonElement) {
    return
  }

  event.preventDefault()
  event.currentTarget.requestSubmit()
}

export function HistoryPage() {
  const [reports, setReports] = useState<DailyReport[]>([])
  const [selectedReport, setSelectedReport] = useState<DailyReport | null>(null)
  const [member, setMember] = useState('')
  const [area, setArea] = useState('')
  const [status, setStatus] = useState<ReportStatus | ''>('')
  const [isLoading, setIsLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const [error, setError] = useState('')
  const [feedback, setFeedback] = useState('')

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
    () => filterHistoryReports(reports, { member, area, status }),
    [reports, member, area, status],
  )

  async function handleSave(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selectedReport) {
      return
    }

    const formData = new FormData(event.currentTarget)
    const payload: UpdateDailyReportRequest = {
      area: requiredField(formData, 'area'),
      title: requiredField(formData, 'title'),
      description: requiredField(formData, 'description'),
      participants: optionalField(formData, 'participants'),
      environment: requiredField(formData, 'environment'),
      recordType: requiredField(formData, 'recordType'),
      decisions: requiredField(formData, 'decisions'),
      testsAndObservations: requiredField(formData, 'testsAndObservations'),
      problems: requiredField(formData, 'problems'),
      evidenceLinks: requiredField(formData, 'evidenceLinks'),
      toolsUsed: optionalField(formData, 'toolsUsed'),
      pendingItems: optionalField(formData, 'pendingItems'),
      finalNotes: optionalField(formData, 'finalNotes'),
    }

    setIsSaving(true)
    setFeedback('')

    try {
      const updated = await updateReport(selectedReport.id, payload)
      setReports((current) => current.map((report) => report.id === updated.id ? updated : report))
      setSelectedReport(updated)
      setFeedback('Edição salva.')
    } catch (requestError: unknown) {
      setFeedback(
        requestError instanceof Error
          ? requestError.message
          : 'Não foi possível salvar a edição.',
      )
    } finally {
      setIsSaving(false)
    }
  }

  async function handleDelete() {
    if (!selectedReport) {
      return
    }

    const confirmed = window.confirm(
      `Excluir o registro de ${selectedReport.memberName} em ${formatDate(selectedReport.reportDate)}? ` +
      'Depois disso, essa pessoa poderá preencher novamente esta data.',
    )

    if (!confirmed) {
      return
    }

    setIsDeleting(true)
    setFeedback('')

    try {
      await deleteReport(selectedReport.id)
      setReports((current) => current.filter((report) => report.id !== selectedReport.id))
      setSelectedReport(null)
      setFeedback('Registro excluído. A pessoa já pode preencher novamente essa data.')
    } catch (requestError: unknown) {
      setFeedback(
        requestError instanceof Error
          ? requestError.message
          : 'Não foi possível excluir o registro.',
      )
    } finally {
      setIsDeleting(false)
    }
  }

  return (
    <div className="page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Memória do projeto</span>
          <h1>Histórico de registros</h1>
          <p>Abra uma resposta para ver todos os campos e corrigir algo quando necessário.</p>
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

      {feedback && !selectedReport && <div className="feedback-message page-feedback">{feedback}</div>}

      <section className="history-layout">
        <div className="history-list" aria-live="polite">
          {isLoading ? (
            <div className="empty-state state-message">
              <h2>Carregando registros...</h2>
            </div>
          ) : error ? (
            <div className="empty-state state-message error">
              <h2>Não foi possível carregar os registros.</h2>
              <p>{error}</p>
            </div>
          ) : filteredReports.length > 0 ? (
            filteredReports.map((report) => (
              <button
                className={selectedReport?.id === report.id ? 'history-row active' : 'history-row'}
                key={report.id}
                type="button"
                onClick={() => {
                  setSelectedReport(report)
                  setFeedback('')
                }}
              >
                <span>{formatDate(report.reportDate)}</span>
                <strong>{report.memberName}</strong>
                <small>{statusLabels[report.status]} · {report.area}</small>
                <p>{report.title}</p>
              </button>
            ))
          ) : (
            <div className="empty-state">
              <span aria-hidden="true">0</span>
              <h2>Nenhum registro encontrado</h2>
              <p>{reports.length > 0 ? 'Tente remover um dos filtros para ampliar a busca.' : 'Os registros enviados aparecerão aqui.'}</p>
            </div>
          )}
        </div>

        <aside className="history-detail">
          {!selectedReport ? (
            <div className="empty-state compact-empty">
              <span aria-hidden="true">↗</span>
              <h2>Selecione um registro</h2>
              <p>O conteúdo completo aparece aqui para leitura e edição.</p>
            </div>
          ) : (
            <form className="edit-form" key={selectedReport.id} onKeyDown={submitOnEnter} onSubmit={handleSave}>
              <div className="detail-heading">
                <div>
                  <span className="eyebrow">{formatDate(selectedReport.reportDate)}</span>
                  <h2>{selectedReport.memberName}</h2>
                  <p>{statusLabels[selectedReport.status]}</p>
                </div>
                <div className="detail-actions">
                  <button className="button ghost danger small" type="button" disabled={isSaving || isDeleting} onClick={handleDelete}>
                    {isDeleting ? 'Excluindo...' : 'Excluir registro'}
                  </button>
                  <button className="button primary small" type="submit" disabled={isSaving || isDeleting}>
                    {isSaving ? 'Salvando...' : 'Salvar edição'}
                  </button>
                </div>
              </div>

              {feedback && <div className="feedback-message page-feedback">{feedback}</div>}

              <label>
                Área
                <input name="area" required maxLength={80} defaultValue={selectedReport.area} />
              </label>
              <label>
                Objetivo do dia
                <input name="title" required maxLength={160} defaultValue={selectedReport.title} />
              </label>
              <label>
                O que foi feito
                <textarea name="description" required rows={4} defaultValue={selectedReport.description} />
              </label>
              <label>
                Participantes envolvidos
                <input name="participants" defaultValue={valueOrEmpty(selectedReport.participants)} />
              </label>
              <div className="form-grid two-columns">
                <label>
                  Local/ambiente
                  <input name="environment" required maxLength={120} defaultValue={valueOrEmpty(selectedReport.environment)} />
                </label>
                <label>
                  Tipo de registro
                  <input name="recordType" required maxLength={80} defaultValue={valueOrEmpty(selectedReport.recordType)} />
                </label>
              </div>
              <label>
                Decisões tomadas
                <textarea name="decisions" required rows={3} defaultValue={valueOrEmpty(selectedReport.decisions)} />
              </label>
              <label>
                Testes, observações ou dados coletados
                <textarea name="testsAndObservations" required rows={3} defaultValue={valueOrEmpty(selectedReport.testsAndObservations)} />
              </label>
              <label>
                Problemas, dificuldades ou riscos
                <textarea name="problems" required rows={3} defaultValue={valueOrEmpty(selectedReport.problems)} />
              </label>
              <label>
                Evidências geradas
                <textarea name="evidenceLinks" rows={3} defaultValue={valueOrEmpty(selectedReport.evidenceLinks)} />
              </label>
              {selectedReport.attachments && selectedReport.attachments.length > 0 && (
                <div className="evidence-upload-card compact">
                  <strong>Arquivos anexados</strong>
                  <ul className="attachment-list">
                    {selectedReport.attachments.map((attachment) => (
                      <li key={attachment.id}>
                        <span>{attachment.originalFilename}</span>
                        <a
                          className="attachment-download"
                          href={attachmentHref(attachment.downloadUrl)}
                          download={attachment.originalFilename}
                        >
                          Baixar · {formatFileSize(attachment.sizeBytes)}
                        </a>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              <div className="form-grid two-columns">
                <label>
                  Uso de IA/ferramentas
                  <input name="toolsUsed" defaultValue={valueOrEmpty(selectedReport.toolsUsed)} />
                </label>
                <label>
                  Pendências geradas
                  <input name="pendingItems" defaultValue={valueOrEmpty(selectedReport.pendingItems)} />
                </label>
              </div>
              <label>
                Observação final
                <textarea name="finalNotes" rows={3} defaultValue={valueOrEmpty(selectedReport.finalNotes)} />
              </label>
            </form>
          )}
        </aside>
      </section>
    </div>
  )
}
