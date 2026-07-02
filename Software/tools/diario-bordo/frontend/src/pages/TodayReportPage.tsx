import { useEffect, useState, type FormEvent } from 'react'
import { getMembers } from '../api/membersApi'
import {
  createNoActivityReport,
  createTodayReport,
} from '../api/reportsApi'
import type { Member } from '../types/member'
import type { CreateTodayReportRequest } from '../types/report'

type Feedback = {
  type: 'success' | 'error'
  message: string
}

function getTodayLabel() {
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo',
  }).format(new Date())
}

function optionalField(formData: FormData, name: string) {
  const value = formData.get(name)?.toString().trim()
  return value || undefined
}

export function TodayReportPage() {
  const [members, setMembers] = useState<Member[]>([])
  const [selectedMemberId, setSelectedMemberId] = useState('')
  const [area, setArea] = useState('')
  const [isLoadingMembers, setIsLoadingMembers] = useState(true)
  const [membersError, setMembersError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [feedback, setFeedback] = useState<Feedback | null>(null)

  useEffect(() => {
    let isCurrent = true

    getMembers()
      .then((data) => {
        if (isCurrent) {
          setMembers(data)
          setMembersError('')
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
  }, [])

  function handleMemberChange(memberId: string) {
    setSelectedMemberId(memberId)
    const member = members.find((item) => item.id === memberId)
    setArea(member?.defaultArea ?? '')
    setFeedback(null)
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = event.currentTarget
    const formData = new FormData(form)
    const minutes = optionalField(formData, 'timeSpentMinutes')

    const payload: CreateTodayReportRequest = {
      memberId: selectedMemberId,
      area: area.trim(),
      title: formData.get('title')?.toString().trim() ?? '',
      description: formData.get('description')?.toString().trim() ?? '',
      problems: optionalField(formData, 'problems'),
      solution: optionalField(formData, 'solution'),
      nextSteps: optionalField(formData, 'nextSteps'),
      evidenceLinks: optionalField(formData, 'evidenceLinks'),
      timeSpentMinutes: minutes ? Number(minutes) : undefined,
    }

    setIsSubmitting(true)
    setFeedback(null)

    try {
      await createTodayReport(payload)
      form.reset()
      setSelectedMemberId('')
      setArea('')
      setFeedback({ type: 'success', message: 'Relatório salvo com sucesso.' })
    } catch (error: unknown) {
      setFeedback({
        type: 'error',
        message: error instanceof Error ? error.message : 'Não foi possível salvar o relatório.',
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  async function handleNoActivity() {
    if (!selectedMemberId) {
      setFeedback({
        type: 'error',
        message: 'Selecione um integrante antes de marcar o dia sem atividade.',
      })
      return
    }

    setIsSubmitting(true)
    setFeedback(null)

    try {
      await createNoActivityReport({ memberId: selectedMemberId })
      setSelectedMemberId('')
      setArea('')
      setFeedback({
        type: 'success',
        message: 'Dia sem atividade registrado com sucesso.',
      })
    } catch (error: unknown) {
      setFeedback({
        type: 'error',
        message: error instanceof Error ? error.message : 'Não foi possível registrar o dia sem atividade.',
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="page narrow-page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Registro diário</span>
          <h1>O que aconteceu hoje?</h1>
          <p>Registre o avanço enquanto os detalhes ainda estão frescos.</p>
        </div>
        <div className="date-chip">
          <span>Data oficial</span>
          <strong>{getTodayLabel()}</strong>
        </div>
      </header>

      <form className="report-form" onSubmit={handleSubmit}>
        <section className="form-section">
          <div className="form-section-heading">
            <span>01</span>
            <div>
              <h2>Quem está registrando?</h2>
              <p>Identifique o integrante e a frente de trabalho.</p>
            </div>
          </div>
          <div className="form-grid two-columns">
            <label>
              Integrante
              <select
                name="memberId"
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
              {membersError && <span className="field-state error">{membersError}</span>}
              {!isLoadingMembers && !membersError && members.length === 0 && (
                <span className="field-state">Nenhum integrante ativo encontrado.</span>
              )}
            </label>
            <label>
              Área
              <input
                name="area"
                required
                maxLength={80}
                value={area}
                onChange={(event) => setArea(event.target.value)}
                placeholder="Ex.: Backend / Software"
              />
            </label>
          </div>
        </section>

        <section className="form-section">
          <div className="form-section-heading">
            <span>02</span>
            <div>
              <h2>Atividade realizada</h2>
              <p>Descreva o trabalho de forma objetiva.</p>
            </div>
          </div>
          <div className="form-grid">
            <label>
              Título da atividade
              <input name="title" required maxLength={160} placeholder="Ex.: Teste do sensor de presença" />
            </label>
            <label>
              Descrição do que foi feito
              <textarea name="description" required rows={5} placeholder="Conte os principais avanços do dia..." />
            </label>
            <div className="form-grid two-columns">
              <label>
                Dificuldades encontradas
                <textarea name="problems" rows={4} placeholder="O que impediu ou atrasou o trabalho?" />
              </label>
              <label>
                Solução ou decisão tomada
                <textarea name="solution" rows={4} placeholder="Como o grupo respondeu?" />
              </label>
            </div>
          </div>
        </section>

        <section className="form-section">
          <div className="form-section-heading">
            <span>03</span>
            <div>
              <h2>Próximos passos e evidências</h2>
              <p>Deixe o caminho preparado para a próxima atividade.</p>
            </div>
          </div>
          <div className="form-grid">
            <label>
              Próximo passo
              <input name="nextSteps" placeholder="Ex.: Repetir o teste com a nova configuração" />
            </label>
            <div className="form-grid evidence-grid">
              <label>
                Links de evidência
                <textarea name="evidenceLinks" rows={3} placeholder="Cole um link por linha" />
              </label>
              <label>
                Tempo aproximado
                <span className="input-with-suffix">
                  <input name="timeSpentMinutes" type="number" min="0" placeholder="60" />
                  <span>min</span>
                </span>
              </label>
            </div>
          </div>
        </section>

        {feedback && (
          <div className={`feedback-message ${feedback.type}`} role="status">
            {feedback.message}
          </div>
        )}

        <div className="form-actions">
          <button
            className="button ghost"
            type="button"
            disabled={isSubmitting}
            onClick={handleNoActivity}
          >
            Não fiz atividade hoje
          </button>
          <button
            className="button primary"
            type="submit"
            disabled={
              isSubmitting ||
              isLoadingMembers ||
              Boolean(membersError) ||
              members.length === 0
            }
          >
            {isSubmitting ? 'Salvando...' : 'Salvar relatório'}
          </button>
        </div>
      </form>
    </div>
  )
}
