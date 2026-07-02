import { useState, type FormEvent } from 'react'
import { areas, members } from '../data/mockData'

function getTodayLabel() {
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo',
  }).format(new Date())
}

export function TodayReportPage() {
  const [feedback, setFeedback] = useState('')

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setFeedback('Relatório salvo localmente para demonstração. Nenhum dado foi enviado.')
    event.currentTarget.reset()
  }

  function handleNoActivity() {
    setFeedback('Registro de dia sem atividade marcado apenas nesta demonstração.')
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
              <select name="member" required defaultValue="">
                <option value="" disabled>Selecione seu nome</option>
                {members.map((member) => <option key={member}>{member}</option>)}
              </select>
            </label>
            <label>
              Área
              <select name="area" required defaultValue="">
                <option value="" disabled>Selecione a área</option>
                {areas.map((area) => <option key={area}>{area}</option>)}
              </select>
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
              <input name="title" required placeholder="Ex.: Teste do sensor de presença" />
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
              <input name="nextStep" placeholder="Ex.: Repetir o teste com a nova configuração" />
            </label>
            <div className="form-grid evidence-grid">
              <label>
                Links de evidência
                <textarea name="evidence" rows={3} placeholder="Cole um link por linha" />
              </label>
              <label>
                Tempo aproximado
                <span className="input-with-suffix">
                  <input name="minutes" type="number" min="1" placeholder="60" />
                  <span>min</span>
                </span>
              </label>
            </div>
          </div>
        </section>

        {feedback && <div className="feedback-message" role="status">{feedback}</div>}

        <div className="form-actions">
          <button className="button ghost" type="button" onClick={handleNoActivity}>
            Não fiz atividade hoje
          </button>
          <button className="button primary" type="submit">Salvar relatório</button>
        </div>
      </form>
    </div>
  )
}
