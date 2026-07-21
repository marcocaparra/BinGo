import { useCallback, useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import { checkReportExists, createNoActivityReport, createTodayReport } from '../api/reportsApi'
import { getMembers } from '../api/membersApi'
import { ATTACHMENTS_ENABLED } from '../config/api'
import type { AuthRole } from '../types/auth'
import type { Member } from '../types/member'
import type { CreateTodayReportRequest, ReportExistence } from '../types/report'

type Feedback = {
  type: 'success' | 'error'
  message: string
}

type SuccessState = {
  memberName: string
  reportDate: string
}

type TodayReportPageProps = {
  role: AuthRole
}

const requiredReportFields = [
  'title',
  'description',
  'environment',
  'recordType',
  'decisions',
  'testsAndObservations',
  'problems',
]

const MAX_ATTACHMENT_COUNT = 8
const MAX_ATTACHMENT_TOTAL_BYTES = 96 * 1024 * 1024
const MAX_IMAGE_BYTES = 10 * 1024 * 1024
const MAX_DOCUMENT_BYTES = 25 * 1024 * 1024
const MAX_VIDEO_BYTES = 64 * 1024 * 1024

const allowedEvidenceExtensions = new Set([
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'mp4',
  'mov',
  'webm',
  'pdf',
  'doc',
  'docx',
  'ppt',
  'pptx',
  'xls',
  'xlsx',
  'txt',
  'md',
  'csv',
  'dxf',
])

function todayIsoDate() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
}

function getDateLabel(date: string) {
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${date}T12:00:00Z`))
}

function optionalField(formData: FormData, name: string) {
  const value = formData.get(name)?.toString().trim()
  return value || undefined
}

function requiredField(formData: FormData, name: string) {
  return formData.get(name)?.toString().trim() ?? ''
}

function extensionOf(filename: string) {
  return filename.split('.').pop()?.toLowerCase() ?? ''
}

function maxBytesForFile(file: File) {
  const extension = extensionOf(file.name)
  if (['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(extension)) {
    return MAX_IMAGE_BYTES
  }
  if (['mp4', 'mov', 'webm'].includes(extension)) {
    return MAX_VIDEO_BYTES
  }
  return MAX_DOCUMENT_BYTES
}

function formatFileSize(sizeBytes: number) {
  if (sizeBytes < 1024 * 1024) {
    return `${Math.max(1, Math.round(sizeBytes / 1024))} KB`
  }
  return `${(sizeBytes / 1024 / 1024).toFixed(1).replace('.', ',')} MB`
}

function validateEvidenceFiles(files: File[]) {
  if (files.length > MAX_ATTACHMENT_COUNT) {
    return `Envie no máximo ${MAX_ATTACHMENT_COUNT} arquivos.`
  }

  const totalBytes = files.reduce((sum, file) => sum + file.size, 0)
  if (totalBytes > MAX_ATTACHMENT_TOTAL_BYTES) {
    return 'Os anexos podem somar no máximo 96 MB.'
  }

  for (const file of files) {
    const extension = extensionOf(file.name)
    if (!allowedEvidenceExtensions.has(extension)) {
      return `O arquivo ${file.name} usa um formato que ainda não aceitamos.`
    }

    const maxBytes = maxBytesForFile(file)
    if (file.size > maxBytes) {
      return `${file.name} passa do limite de ${formatFileSize(maxBytes)}.`
    }
  }

  return ''
}

function OptionalTag() {
  return <span className="optional-tag">Opcional</span>
}

function submitOnEnter(event: KeyboardEvent<HTMLFormElement>) {
  if (event.key !== 'Enter' || event.shiftKey || event.nativeEvent.isComposing) {
    return
  }

  if (event.target instanceof HTMLButtonElement) {
    return
  }

  const submitButton = event.currentTarget.querySelector<HTMLButtonElement>('button[type="submit"]')
  if (submitButton?.disabled) {
    return
  }

  event.preventDefault()
  event.currentTarget.requestSubmit()
}

export function TodayReportPage({ role }: TodayReportPageProps) {
  const formRef = useRef<HTMLFormElement | null>(null)
  const [members, setMembers] = useState<Member[]>([])
  const [selectedMemberId, setSelectedMemberId] = useState('')
  const [area, setArea] = useState('')
  const [reportDate, setReportDate] = useState(todayIsoDate)
  const [isLoadingMembers, setIsLoadingMembers] = useState(true)
  const [membersError, setMembersError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [isCheckingExisting, setIsCheckingExisting] = useState(false)
  const [existingReport, setExistingReport] = useState<ReportExistence | null>(null)
  const [feedback, setFeedback] = useState<Feedback | null>(null)
  const [success, setSuccess] = useState<SuccessState | null>(null)
  const [filledNotice, setFilledNotice] = useState<SuccessState | null>(null)
  const [isReportReady, setIsReportReady] = useState(false)
  const [evidenceFiles, setEvidenceFiles] = useState<File[]>([])
  const [fileError, setFileError] = useState('')

  useEffect(() => {
    let isCurrent = true

    getMembers()
      .then((data) => {
        if (!isCurrent) {
          return
        }

        setMembers(data)
        setMembersError('')

        if (role === 'ADMIN') {
          const marco = data.find((member) => member.name.toLowerCase().includes('marco'))
          if (marco) {
            setSelectedMemberId(marco.id)
            setArea(marco.defaultArea ?? '')
          }
        }
      })
      .catch((error: unknown) => {
        if (isCurrent) {
          setMembersError(
            error instanceof Error
              ? error.message
              : 'Não foi possível carregar os integrantes.',
          )
        }
      })
      .finally(() => {
        if (isCurrent) {
          setIsLoadingMembers(false)
        }
      })

    return () => {
      isCurrent = false
    }
  }, [role])

  useEffect(() => {
    if (!selectedMemberId || !reportDate) {
      return
    }

    let isCurrent = true

    async function validateExistingReport() {
      setIsCheckingExisting(true)
      setExistingReport(null)

      try {
        const response = await checkReportExists(selectedMemberId, reportDate)
        if (isCurrent) {
          setExistingReport(response.exists ? response : null)
        }
      } catch (error: unknown) {
        if (isCurrent) {
          setFeedback({
            type: 'error',
            message: error instanceof Error ? error.message : 'Não foi possível validar se o registro já existe.',
          })
        }
      } finally {
        if (isCurrent) {
          setIsCheckingExisting(false)
        }
      }
    }

    void validateExistingReport()

    return () => {
      isCurrent = false
    }
  }, [selectedMemberId, reportDate])

  const updateReportReadiness = useCallback(() => {
    const form = formRef.current
    if (!form || existingReport || isLoadingMembers || Boolean(membersError)) {
      setIsReportReady(false)
      return
    }

    const formData = new FormData(form)
    const requiredFieldsAreFilled = requiredReportFields.every((field) =>
      Boolean(formData.get(field)?.toString().trim()),
    )
    const hasEvidence = Boolean(formData.get('evidenceLinks')?.toString().trim())
      || (ATTACHMENTS_ENABLED && evidenceFiles.length > 0)

    setIsReportReady(Boolean(selectedMemberId && area.trim() && requiredFieldsAreFilled && hasEvidence && !fileError))
  }, [area, evidenceFiles.length, existingReport, fileError, isLoadingMembers, membersError, selectedMemberId])

  useEffect(() => {
    updateReportReadiness()
  }, [updateReportReadiness])

  function handleMemberChange(memberId: string) {
    setSelectedMemberId(memberId)
    const member = members.find((item) => item.id === memberId)
    setArea(member?.defaultArea ?? '')
    setExistingReport(null)
    setFeedback(null)
    setFilledNotice(null)
    window.requestAnimationFrame(updateReportReadiness)
  }

  function handleEvidenceFilesChange(files: FileList | null) {
    const selectedFiles = Array.from(files ?? [])
    const validationMessage = validateEvidenceFiles(selectedFiles)
    setEvidenceFiles(selectedFiles)
    setFileError(validationMessage)
    window.requestAnimationFrame(updateReportReadiness)
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (existingReport) {
      setFeedback({
        type: 'error',
        message: `Você já preencheu o registro de ${getDateLabel(existingReport.reportDate)}.`,
      })
      return
    }

    const form = event.currentTarget
    const formData = new FormData(form)
    const selectedMember = members.find((member) => member.id === selectedMemberId)
    const validationMessage = ATTACHMENTS_ENABLED ? validateEvidenceFiles(evidenceFiles) : ''

    if (validationMessage) {
      setFileError(validationMessage)
      setFeedback({ type: 'error', message: validationMessage })
      return
    }

    const payload: CreateTodayReportRequest = {
      memberId: selectedMemberId,
      reportDate,
      area: area.trim(),
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

    setIsSubmitting(true)
    setFeedback(null)

    try {
      await createTodayReport(payload, ATTACHMENTS_ENABLED ? evidenceFiles : [])
      form.reset()
      setEvidenceFiles([])
      setFileError('')
      setSuccess({
        memberName: selectedMember?.name ?? 'Integrante',
        reportDate,
      })
      setSelectedMemberId(role === 'ADMIN' ? selectedMemberId : '')
      setArea(role === 'ADMIN' ? area : '')
      setReportDate(todayIsoDate())
    } catch (error: unknown) {
      setFeedback({
        type: 'error',
        message: error instanceof Error ? error.message : 'Não foi possível salvar o registro.',
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  async function handleNoActivitySubmit() {
    if (existingReport) {
      setFeedback({
        type: 'error',
        message: `Você já preencheu o registro de ${getDateLabel(existingReport.reportDate)}.`,
      })
      return
    }

    const selectedMember = members.find((member) => member.id === selectedMemberId)
    if (!selectedMemberId || !reportDate) {
      setFeedback({
        type: 'error',
        message: 'Selecione seu nome e a data antes de marcar sem atividade.',
      })
      return
    }

    setIsSubmitting(true)
    setFeedback(null)

    try {
      await createNoActivityReport({
        memberId: selectedMemberId,
        reportDate,
        area: area.trim() || undefined,
      })
      formRef.current?.reset()
      setEvidenceFiles([])
      setFileError('')
      setSuccess({
        memberName: selectedMember?.name ?? 'Integrante',
        reportDate,
      })
      setSelectedMemberId(role === 'ADMIN' ? selectedMemberId : '')
      setArea(role === 'ADMIN' ? area : '')
      setReportDate(todayIsoDate())
    } catch (error: unknown) {
      setFeedback({
        type: 'error',
        message: error instanceof Error ? error.message : 'Não foi possível salvar o registro sem atividade.',
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  const selectedDateIsToday = reportDate === todayIsoDate()
  const isFormLocked = Boolean(existingReport)

  if (success) {
    return (
      <div className="page narrow-page">
        <section className="success-panel">
          <span className="eyebrow">Registro salvo</span>
          <h1 className="success-title"><strong>{success.memberName}</strong>, seu registro foi salvo com sucesso!</h1>
          <p>
            Obrigado por manter o Diário de Bordo vivo. Cada resposta ajuda o BinGo
            a chegar mais organizado na próxima etapa. <strong>Vamos pra cima!</strong>
          </p>
          <div className="success-meta">
            <span>Data registrada</span>
            <strong>{getDateLabel(success.reportDate)}</strong>
          </div>
          <button
            className="button primary"
            type="button"
            onClick={() => {
              setFilledNotice(success)
              setSuccess(null)
            }}
          >
            Voltar ao início
          </button>
        </section>
      </div>
    )
  }

  return (
    <div className="page narrow-page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Registro diário</span>
          <h1>O que você fez?</h1>
          <p>Escolha a data do registro e preencha o suficiente para virar diário oficial depois.</p>
        </div>
        <div className="date-chip">
          <span>Data do registro</span>
          <label className="date-input-shell">
            <input
              aria-label="Data do registro"
              type="date"
              value={reportDate}
              max={todayIsoDate()}
              onChange={(event) => {
                const nextDate = event.target.value > todayIsoDate() ? todayIsoDate() : event.target.value
                setReportDate(nextDate)
                setExistingReport(null)
                setFilledNotice(null)
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

      {filledNotice && (
        <section className="already-done-panel">
          <div>
            <span className="eyebrow">Registro recebido</span>
            <h2 className="already-done-title">
              <strong>{filledNotice.memberName}</strong>, você já preencheu o dia <strong>{getDateLabel(filledNotice.reportDate)}</strong>.
            </h2>
            <p>Se precisar corrigir algo, fale com a coordenação para editar pelo histórico.</p>
          </div>
        </section>
      )}

      {existingReport && (
        <section className="already-done-panel">
          <div>
            <span className="eyebrow">Registro já existe</span>
            <h2 className="already-done-title">
              <strong>{existingReport.memberName ?? 'Você'}</strong> já preencheu o dia <strong>{getDateLabel(existingReport.reportDate)}</strong>.
            </h2>
            <p>Para evitar duplicidade, este registro não pode ser enviado de novo.</p>
          </div>
        </section>
      )}

      <form
        className="report-form"
        ref={formRef}
        onInput={updateReportReadiness}
        onKeyDown={submitOnEnter}
        onSubmit={handleSubmit}
      >
        <section className="form-section">
          <div className="form-section-heading">
            <span>01</span>
            <div>
              <h2>Identificação</h2>
              <p>Quem está registrando e em qual frente trabalhou.</p>
            </div>
          </div>
          <div className="form-grid two-columns">
            <label className="select-label">
              Eu
              <span className="select-input-shell">
                <select
                  required
                  value={selectedMemberId}
                  disabled={isLoadingMembers || Boolean(membersError)}
                  onChange={(event) => handleMemberChange(event.target.value)}
                >
                  <option value="" disabled>
                    {isLoadingMembers ? 'Carregando integrantes...' : 'Selecione seu nome'}
                  </option>
                  {members.map((member) => (
                    <option value={member.id} key={member.id}>{member.name}</option>
                  ))}
                </select>
                <span className="date-input-icon select-input-icon" aria-hidden="true">
                  <svg viewBox="0 0 24 24">
                    <path d="M7 9l5 5 5-5" />
                  </svg>
                </span>
              </span>
              {membersError && <span className="field-state error">{membersError}</span>}
            </label>
            <label>
              Frente principal/área
              <input
                required
                maxLength={80}
                value={area}
                disabled={isFormLocked}
                onChange={(event) => {
                  setArea(event.target.value)
                  window.requestAnimationFrame(updateReportReadiness)
                }}
                placeholder="Ex.: Software, Hardware, Gestão"
              />
            </label>
          </div>
        </section>

        <fieldset className="form-fieldset" disabled={isFormLocked}>
          <section className="form-section">
            <div className="form-section-heading">
              <span>02</span>
              <div>
                <h2>Essencial do dia</h2>
                <p>O mínimo necessário para o registro ficar claro e útil.</p>
              </div>
            </div>
            <div className="form-grid">
              <label>
                Objetivo do dia
                <input name="title" required maxLength={160} placeholder="Ex.: Revisar o fluxo do formulário" />
              </label>
              <label>
                O que foi feito
                <textarea name="description" required rows={5} placeholder="Conte o que avançou, mesmo que tenha sido pouco." />
              </label>
            </div>
          </section>

          <section className="form-section">
            <div className="form-section-heading">
              <span>03</span>
              <div>
                <h2>Contexto do registro</h2>
                <p>Esses campos ajudam a transformar resposta solta em diário oficial.</p>
              </div>
            </div>
            <div className="form-grid">
              <div className="form-grid two-columns">
                <label>
                  Local/ambiente
                  <input name="environment" required maxLength={120} placeholder="Ex.: laboratório, casa, online" />
                </label>
                <label>
                  Tipo de registro
                  <input name="recordType" required maxLength={80} placeholder="Ex.: teste, desenvolvimento, reunião" />
                </label>
              </div>
              <label>
                <span className="label-line">Participantes envolvidos <OptionalTag /></span>
                <input name="participants" placeholder="Ex.: Marco, Gustavo e Guilherme" />
              </label>
              <label>
                Decisões tomadas
                <textarea name="decisions" required rows={3} placeholder="Se não houve decisão, registre isso de forma simples." />
              </label>
              <label>
                Testes, observações ou dados coletados
                <textarea name="testsAndObservations" required rows={3} placeholder="Inclua observações, resultados ou aprendizados do dia." />
              </label>
            </div>
          </section>

          <section className="form-section">
            <div className="form-section-heading">
              <span>04</span>
              <div>
                <h2>Dificuldades e evidências</h2>
                <p>Mostre o que comprova o trabalho e o que ainda pode atrapalhar.</p>
              </div>
            </div>
            <div className="form-grid">
              <label>
                Problemas, dificuldades ou riscos
                <textarea name="problems" required rows={3} placeholder="Se não teve problema, escreva que não houve dificuldade relevante." />
              </label>
              <label>
                Evidências geradas
                <textarea
                  name="evidenceLinks"
                  rows={4}
                  placeholder={ATTACHMENTS_ENABLED
                    ? 'Cole links, explique evidências ou descreva arquivos importantes. Também dá para anexar arquivos abaixo.'
                    : 'Cole links compartilháveis do Google Drive, OneDrive, GitHub ou outra fonte de evidência.'}
                />
              </label>
              {ATTACHMENTS_ENABLED && <div className="evidence-upload-card">
                <div>
                  <strong>Anexar arquivos</strong>
                  <p>Imagens até 10 MB, documentos até 25 MB e vídeos até 64 MB. Máximo de 8 arquivos.</p>
                </div>
                <label className="file-dropzone">
                  <input
                    type="file"
                    multiple
                    accept=".jpg,.jpeg,.png,.webp,.gif,.mp4,.mov,.webm,.pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt,.md,.csv,.dxf"
                    onChange={(event) => handleEvidenceFilesChange(event.target.files)}
                  />
                  <span>Escolher evidências</span>
                  <small>Prints, vídeos, PDF, DOC, DXF e outros arquivos do projeto</small>
                </label>
                {fileError && <span className="field-state error">{fileError}</span>}
                {evidenceFiles.length > 0 && (
                  <ul className="attachment-list">
                    {evidenceFiles.map((file) => (
                      <li key={`${file.name}-${file.size}-${file.lastModified}`}>
                        <span>{file.name}</span>
                        <strong>{formatFileSize(file.size)}</strong>
                      </li>
                    ))}
                  </ul>
                )}
              </div>}
              <div className="form-grid two-columns">
                <label>
                  <span className="label-line">Uso de IA/ferramentas <OptionalTag /></span>
                  <input name="toolsUsed" placeholder="Ex.: ChatGPT, Supabase, Arduino IDE" />
                </label>
                <label>
                  <span className="label-line">Pendências geradas <OptionalTag /></span>
                  <input name="pendingItems" placeholder="Algo que ficou para resolver depois" />
                </label>
              </div>
              <label>
                <span className="label-line">Observação final <OptionalTag /></span>
                <textarea name="finalNotes" rows={3} placeholder="Opcional" />
              </label>
            </div>
          </section>
        </fieldset>

        {feedback && (
          <div className={`feedback-message ${feedback.type}`} role="status">
            {feedback.message}
          </div>
        )}

        <div className="form-actions">
          <button
            className="button secondary"
            type="button"
            disabled={
              isSubmitting ||
              isCheckingExisting ||
              isFormLocked ||
              isLoadingMembers ||
              Boolean(membersError) ||
              members.length === 0 ||
              !selectedMemberId
            }
            onClick={handleNoActivitySubmit}
          >
            Não trabalhei no projeto
          </button>
          <button
            className="button primary"
            type="submit"
            disabled={
              isSubmitting ||
              isCheckingExisting ||
              isFormLocked ||
              isLoadingMembers ||
              Boolean(membersError) ||
              members.length === 0 ||
              !isReportReady
            }
          >
            {isSubmitting ? 'Salvando...' : isCheckingExisting ? 'Validando...' : 'Salvar registro'}
          </button>
        </div>
      </form>
    </div>
  )
}
