import { useRef, useState, type FormEvent, type KeyboardEvent } from 'react'
import { accessWithPin } from '../api/authApi'
import { storeSession } from '../auth/session'
import { LoadingScreen } from '../components/LoadingScreen'
import type { AuthRole, AuthSession } from '../types/auth'

type LoginPageProps = {
  onLogin: (session: AuthSession) => void
}

type LoadingState = {
  title: string
  subtitle: string
}

const roleOptions: Array<{
  role: AuthRole
  label: string
  description: string
  accent: 'team' | 'admin'
  icon: string
  chips: string[]
}> = [
  {
    role: 'TEAM',
    label: 'Equipe',
    description: 'Preencher o registro diário de trabalho',
    accent: 'team',
    icon: '📝',
    chips: ['Registro diário', 'Evidências', 'Contexto'],
  },
  {
    role: 'ADMIN',
    label: 'Coordenação',
    description: 'Acompanhar respostas, histórico e exportação',
    accent: 'admin',
    icon: '🚀',
    chips: ['Painel do dia', 'Histórico', 'Markdown'],
  },
]

function EyeIcon({ visible }: { visible: boolean }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M2.8 12s3.2-5.2 9.2-5.2S21.2 12 21.2 12s-3.2 5.2-9.2 5.2S2.8 12 2.8 12Z" />
      <circle cx="12" cy="12" r={visible ? '3.2' : '2.4'} />
      {!visible && <path className="eye-slash" d="M4 20 20 4" />}
    </svg>
  )
}

export function LoginPage({ onLogin }: LoginPageProps) {
  const errorTimerRef = useRef<number | null>(null)
  const [step, setStep] = useState<'role' | 'pin'>('role')
  const [role, setRole] = useState<AuthRole>('TEAM')
  const [pin, setPin] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [loadingState, setLoadingState] = useState<LoadingState | null>(null)
  const [error, setError] = useState('')
  const [isErrorLeaving, setIsErrorLeaving] = useState(false)
  const [isPinVisible, setIsPinVisible] = useState(false)

  const canSubmitPin = pin.length === 6 && !isSubmitting
  const roleLabel = role === 'ADMIN' ? 'Coordenação' : 'Equipe'

  function showError(message: string) {
    if (errorTimerRef.current) {
      window.clearTimeout(errorTimerRef.current)
      errorTimerRef.current = null
    }

    setIsErrorLeaving(false)
    setError(message)
  }

  function hideErrorSmoothly() {
    if (!error || isErrorLeaving) {
      return
    }

    setIsErrorLeaving(true)
    if (errorTimerRef.current) {
      window.clearTimeout(errorTimerRef.current)
    }

    errorTimerRef.current = window.setTimeout(() => {
      setError('')
      setIsErrorLeaving(false)
      errorTimerRef.current = null
    }, 260)
  }

  function handleRoleSelect(nextRole: AuthRole) {
    setRole(nextRole)
    setPin('')
    hideErrorSmoothly()
    setIsPinVisible(false)
    setLoadingState({
      title: 'Preparando acesso',
      subtitle: 'Abrindo a tela de PIN...',
    })

    window.setTimeout(() => {
      setStep('pin')
      setLoadingState(null)
    }, 560)
  }

  function handleBackToRole() {
    hideErrorSmoothly()
    setPin('')
    setIsPinVisible(false)
    setLoadingState({
      title: 'Voltando para seleção',
      subtitle: 'Preparando os acessos disponíveis...',
    })

    window.setTimeout(() => {
      setStep('role')
      setLoadingState(null)
    }, 520)
  }

  function handleConfirmKey(event: KeyboardEvent<HTMLFormElement>) {
    if (event.key !== 'Enter' || event.shiftKey || event.nativeEvent.isComposing) {
      return
    }

    if (event.target instanceof HTMLButtonElement || !canSubmitPin) {
      return
    }

    event.preventDefault()
    event.currentTarget.requestSubmit()
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!/^\d{6}$/.test(pin)) {
      showError('Digite um PIN de 6 dígitos.')
      return
    }

    setIsSubmitting(true)
    hideErrorSmoothly()

    try {
      const response = await accessWithPin(role, pin)
      const session = {
        role: response.role,
        token: response.token,
        expiresAt: Date.parse(response.expiresAt),
      }
      storeSession(session)
      onLogin(session)
    } catch (requestError: unknown) {
      const message = requestError instanceof Error ? requestError.message : ''
      showError(message.toLowerCase().includes('api') ? message : 'PIN inválido')
    } finally {
      setIsSubmitting(false)
    }
  }

  if (loadingState) {
    return <LoadingScreen title={loadingState.title} subtitle={loadingState.subtitle} />
  }

  return (
    <main className="login-screen">
      <section className={`login-panel access-panel ${step === 'role' ? 'access-panel-role' : 'access-panel-pin'}`}>
        <div className="access-heading">
          <img className="access-logo" src="/bingo-logo.png" alt="BinGo" />
          <h1>{step === 'role' ? 'Quem está acessando?' : 'Digite seu PIN'}</h1>
          <p>
            {step === 'role' ? (
              'Selecione o tipo de acesso para continuar.'
            ) : (
              <>
                Acesso de <strong>{roleLabel}</strong> selecionado.
              </>
            )}
          </p>
        </div>

        {step === 'role' ? (
          <>
            <div className="role-picker access-options" role="radiogroup" aria-label="Tipo de acesso">
              {roleOptions.map((option) => (
                <button
                  className={`role-option access-option-card access-option-${option.accent}`}
                  key={option.role}
                  type="button"
                  role="radio"
                  aria-checked={role === option.role}
                  onClick={() => handleRoleSelect(option.role)}
                >
                  <span className="access-option-icon" aria-hidden="true">
                    <span className="access-option-emoji">{option.icon}</span>
                  </span>
                  <span className="access-option-copy">
                    <strong>{option.label}</strong>
                    <small>{option.description}</small>
                    <span className="access-option-chips">
                      {option.chips.map((chip) => (
                        <span key={chip}>{chip}</span>
                      ))}
                    </span>
                  </span>
                  <span className="access-option-arrow" aria-hidden="true">›</span>
                </button>
              ))}
            </div>

            <div className="access-security-note">
              <span className="security-mark" aria-hidden="true">🔒</span>
              <div>
                <strong>2 níveis de acesso · sessão válida por 8 horas</strong>
                <p>Equipe registra o dia. Coordenação acompanha, edita e exporta.</p>
              </div>
            </div>
          </>
        ) : (
          <>
            <form className="login-form pin-form" onKeyDown={handleConfirmKey} onSubmit={handleSubmit}>
              <label>
                <span>PIN de seis dígitos</span>
                <span className="pin-input-shell">
                  <input
                    autoFocus
                    className="pin-input"
                    inputMode="numeric"
                    maxLength={6}
                    pattern="\d{6}"
                    type={isPinVisible ? 'text' : 'password'}
                  value={pin}
                  onChange={(event) => {
                    setPin(event.target.value.replace(/\D/g, '').slice(0, 6))
                    hideErrorSmoothly()
                  }}
                    placeholder="000000"
                    required
                  />
                  <button
                    className="pin-visibility-button"
                    type="button"
                    aria-label={isPinVisible ? 'Esconder PIN' : 'Mostrar PIN'}
                    onClick={() => setIsPinVisible((current) => !current)}
                  >
                    <EyeIcon visible={isPinVisible} />
                  </button>
                </span>
              </label>

              <div className="login-actions">
                <button className="button secondary" type="button" onClick={handleBackToRole}>
                  Trocar acesso
                </button>
                <button className="button primary" type="submit" disabled={!canSubmitPin}>
                  {isSubmitting ? 'Validando...' : 'Entrar'}
                </button>
              </div>
            </form>

            {error && (
              <div className={`pin-error-card ${isErrorLeaving ? 'is-leaving' : ''}`} role="alert">
                <span className="pin-error-icon" aria-hidden="true">!</span>
                <strong>{error}</strong>
              </div>
            )}
          </>
        )}
      </section>
    </main>
  )
}
