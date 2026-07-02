import { useEffect, useState } from 'react'
import { Navbar } from './components/Navbar'
import { ExportPage } from './pages/ExportPage'
import { HistoryPage } from './pages/HistoryPage'
import { HomePage } from './pages/HomePage'
import { PendingReportsPage } from './pages/PendingReportsPage'
import { TodayReportPage } from './pages/TodayReportPage'

export type Page = 'home' | 'today' | 'history' | 'pending' | 'export'

const pageByHash: Record<string, Page> = {
  '#/home': 'home',
  '#/hoje': 'today',
  '#/historico': 'history',
  '#/pendentes': 'pending',
  '#/exportar': 'export',
}

function getCurrentPage(): Page {
  return pageByHash[window.location.hash] ?? 'home'
}

function App() {
  const [currentPage, setCurrentPage] = useState<Page>(getCurrentPage)

  useEffect(() => {
    const updatePage = () => setCurrentPage(getCurrentPage())
    window.addEventListener('hashchange', updatePage)
    return () => window.removeEventListener('hashchange', updatePage)
  }, [])

  return (
    <div className="app-shell">
      <Navbar currentPage={currentPage} />
      <main>
        {currentPage === 'home' && <HomePage />}
        {currentPage === 'today' && <TodayReportPage />}
        {currentPage === 'history' && <HistoryPage />}
        {currentPage === 'pending' && <PendingReportsPage />}
        {currentPage === 'export' && <ExportPage />}
      </main>
      <footer className="site-footer">
        <span>Diário de Bordo Coletivo</span>
        <span>Projeto BinGo · V0 visual</span>
      </footer>
    </div>
  )
}

export default App
