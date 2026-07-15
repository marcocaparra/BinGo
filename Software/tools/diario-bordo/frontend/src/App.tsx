import { useCallback, useEffect, useRef, useState } from 'react'
import { waitForApiReady } from './api/healthApi'
import { clearSession, getStoredSession } from './auth/session'
import { ApiStartupScreen } from './components/ApiStartupScreen'
import { LoadingScreen } from './components/LoadingScreen'
import { AppSidebar } from './components/Navbar'
import { ExportPage } from './pages/ExportPage'
import { HistoryPage } from './pages/HistoryPage'
import { LoginPage } from './pages/LoginPage'
import { TodayReportPage } from './pages/TodayReportPage'
import type { AuthSession } from './types/auth'

export type Page = 'today' | 'history' | 'export'

type ViewTransitionDocument = Document & {
  startViewTransition?: (callback: () => void) => void
}

function isCompactViewport() {
  return window.matchMedia('(max-width: 980px)').matches
}

const pageByHash: Record<string, Page> = {
  '#/hoje': 'today',
  '#/historico': 'history',
  '#/exportar': 'export',
}

function getCurrentPage(session: AuthSession | null): Page {
  const page = pageByHash[window.location.hash]
  if (!session || session.role === 'TEAM') {
    return 'today'
  }

  return page ?? 'export'
}

function App() {
  const sidebarAnimationRef = useRef<Animation | null>(null)
  const storedSession = getStoredSession()
  const [session, setSession] = useState<AuthSession | null>(() => storedSession)
  const [currentPage, setCurrentPage] = useState<Page>(() => getCurrentPage(storedSession))
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(() => isCompactViewport())
  const [transition, setTransition] = useState<{ title: string; subtitle: string } | null>(null)
  const [apiStatus, setApiStatus] = useState<'checking' | 'ready' | 'unavailable'>('checking')

  const retryApi = useCallback(() => {
    setApiStatus('checking')
    void waitForApiReady().then((ready) => {
      setApiStatus(ready ? 'ready' : 'unavailable')
    })
  }, [])

  useEffect(() => {
    let active = true
    void waitForApiReady().then((ready) => {
      if (active) {
        setApiStatus(ready ? 'ready' : 'unavailable')
      }
    })
    return () => {
      active = false
    }
  }, [])

  useEffect(() => {
    const compactViewport = window.matchMedia('(max-width: 980px)')
    const syncNavigationMode = () => setIsSidebarCollapsed(compactViewport.matches)

    syncNavigationMode()
    compactViewport.addEventListener('change', syncNavigationMode)
    return () => compactViewport.removeEventListener('change', syncNavigationMode)
  }, [])

  useEffect(() => {
    const updatePage = () => {
      const nextPage = getCurrentPage(session)
      const motionDocument = document as ViewTransitionDocument

      if (session && motionDocument.startViewTransition) {
        try {
          motionDocument.startViewTransition(() => setCurrentPage(nextPage))
          return
        } catch {
          setCurrentPage(nextPage)
          return
        }
      }

      setCurrentPage(nextPage)
    }

    window.addEventListener('hashchange', updatePage)
    updatePage()
    return () => window.removeEventListener('hashchange', updatePage)
  }, [session])

  function handleLogin(nextSession: AuthSession) {
    setTransition({
      title: nextSession.role === 'ADMIN' ? 'Carregando painel' : 'Carregando registro',
      subtitle: 'Preparando ambiente de acesso...',
    })

    window.setTimeout(() => {
      setSession(nextSession)
      const nextHash = nextSession.role === 'ADMIN' ? '#/exportar' : '#/hoje'
      window.location.hash = nextHash
      setCurrentPage(getCurrentPage(nextSession))
      setTransition(null)
    }, 780)
  }

  function handleLogout() {
    setTransition({
      title: 'Saindo do acesso',
      subtitle: 'Fechando a sessão e voltando ao início...',
    })

    window.setTimeout(() => {
      clearSession()
      setSession(null)
      setCurrentPage('today')
      window.location.hash = ''
      setTransition(null)
    }, 680)
  }

  function handleToggleSidebar() {
    if (isCompactViewport()) {
      setIsSidebarCollapsed((current) => !current)
      return
    }

    const sidebar = document.querySelector<HTMLElement>('.app-sidebar')
    const shell = document.querySelector<HTMLElement>('.app-shell')
    const nextCollapsed = !isSidebarCollapsed
    const fromWidth = sidebar?.getBoundingClientRect().width
    const toWidth = nextCollapsed ? 96 : 320
    const shouldReduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

    sidebarAnimationRef.current?.cancel()

    if (!sidebar || !fromWidth || shouldReduceMotion || typeof sidebar.animate !== 'function') {
      setIsSidebarCollapsed(nextCollapsed)
      return
    }

    shell?.classList.add(
      'app-sidebar-is-animating',
      nextCollapsed ? 'app-sidebar-is-collapsing' : 'app-sidebar-is-expanding',
    )

    const animation = sidebar.animate(
      [
        { width: `${fromWidth}px` },
        { width: `${toWidth}px` },
      ],
      {
        duration: 460,
        easing: 'cubic-bezier(0.16, 1, 0.3, 1)',
        fill: 'forwards',
      },
    )

    let finished = false
    const finishAnimation = () => {
      if (finished) {
        return
      }

      finished = true
      sidebarAnimationRef.current = null
      setIsSidebarCollapsed(nextCollapsed)
      window.requestAnimationFrame(() => {
        animation.cancel()
        shell?.classList.remove(
          'app-sidebar-is-animating',
          'app-sidebar-is-collapsing',
          'app-sidebar-is-expanding',
        )
      })
    }
    const fallbackTimer = window.setTimeout(finishAnimation, 540)

    sidebarAnimationRef.current = animation
    animation.onfinish = () => {
      window.clearTimeout(fallbackTimer)
      finishAnimation()
    }
    animation.oncancel = () => {
      window.clearTimeout(fallbackTimer)
      sidebarAnimationRef.current = null
      if (finished) {
        return
      }

      shell?.classList.remove(
        'app-sidebar-is-animating',
        'app-sidebar-is-collapsing',
        'app-sidebar-is-expanding',
      )
    }
  }

  function handleNavigationSelect() {
    if (isCompactViewport()) {
      setIsSidebarCollapsed(true)
    }
  }

  if (apiStatus !== 'ready') {
    return <ApiStartupScreen unavailable={apiStatus === 'unavailable'} onRetry={retryApi} />
  }

  if (transition) {
    return <LoadingScreen title={transition.title} subtitle={transition.subtitle} />
  }

  if (!session) {
    return <LoginPage onLogin={handleLogin} />
  }

  return (
    <div className={`app-shell app-shell-${session.role.toLowerCase()}${isSidebarCollapsed ? ' app-sidebar-is-collapsed' : ''}`}>
      <div className="app-layout">
        <AppSidebar
          collapsed={isSidebarCollapsed}
          currentPage={currentPage}
          role={session.role}
          onLogout={handleLogout}
          onNavigate={handleNavigationSelect}
          onToggleCollapse={handleToggleSidebar}
        />
        <main className="app-main">
          <div className="page-transition-stage" key={`${session.role}-${currentPage}`}>
            {currentPage === 'today' && <TodayReportPage role={session.role} />}
            {session.role === 'ADMIN' && currentPage === 'history' && <HistoryPage />}
            {session.role === 'ADMIN' && currentPage === 'export' && <ExportPage />}
          </div>
        </main>
      </div>
    </div>
  )
}

export default App
