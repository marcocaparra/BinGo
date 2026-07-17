type LoadingScreenProps = {
  title?: string
  subtitle?: string
}

export function LoadingScreen({
  title = 'Carregando painel',
  subtitle = 'Preparando ambiente de acesso...',
}: LoadingScreenProps) {
  return (
    <main className="access-loading-screen" aria-label={title}>
      <div className="loading-stage">
        <div className="loading-logo-wrap">
          <span className="loading-logo-glow" aria-hidden="true" />
          <img className="loading-logo" src="/bingo-logo.png" alt="BinGo" />
        </div>
        <div className="loading-copy">
          <h1>{title}</h1>
          <p>{subtitle}</p>
        </div>
        <div className="loading-progress" aria-hidden="true">
          <span />
        </div>
      </div>
    </main>
  )
}
