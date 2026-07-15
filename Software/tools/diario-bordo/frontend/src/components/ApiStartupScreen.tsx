type ApiStartupScreenProps = {
  unavailable?: boolean
  onRetry: () => void
}

export function ApiStartupScreen({ unavailable = false, onRetry }: ApiStartupScreenProps) {
  return (
    <main className="access-loading-screen" aria-live="polite">
      <div className="loading-stage">
        <div className="loading-logo-wrap">
          <span className="loading-logo-glow" aria-hidden="true" />
          <img className="loading-logo" src="/bingo-logo.png" alt="BinGo" />
        </div>
        <div className="loading-copy">
          <h1>{unavailable ? 'O servidor demorou mais que o esperado' : 'Preparando o Diário de Bordo...'}</h1>
          <p>
            {unavailable
              ? 'Confira sua conexão e tente novamente.'
              : 'A hospedagem gratuita pode levar alguns segundos para acordar.'}
          </p>
        </div>
        {unavailable ? (
          <button className="button primary" type="button" onClick={onRetry}>
            Tentar novamente
          </button>
        ) : (
          <div className="loading-progress" aria-hidden="true"><span /></div>
        )}
      </div>
    </main>
  )
}
