export function PendingReportsPage() {
  return (
    <div className="page">
      <header className="page-header split-header">
        <div>
          <span className="eyebrow">Acompanhamento</span>
          <h1>Relatórios pendentes</h1>
          <p>Registros que ainda precisam ser preenchidos ou marcados sem atividade.</p>
        </div>
        <div className="count-box attention">
          <strong>—</strong>
          <span>integração futura</span>
        </div>
      </header>

      <section className="pending-list">
        <div className="empty-state state-message">
          <h2>Pendências ainda não disponíveis</h2>
          <p>A listagem automática de pendências será integrada em uma próxima etapa.</p>
          <a className="button primary" href="#/hoje">Preencher relatório de hoje</a>
        </div>
      </section>
    </div>
  )
}
