import type { Page } from '../App'

type NavItem = {
  label: string
  page: Page
  href: string
}

const navItems: NavItem[] = [
  { label: 'Início', page: 'home', href: '#/home' },
  { label: 'Relatório Diário', page: 'today', href: '#/hoje' },
  { label: 'Histórico', page: 'history', href: '#/historico' },
  { label: 'Pendentes', page: 'pending', href: '#/pendentes' },
  { label: 'Exportar', page: 'export', href: '#/exportar' },
]

type NavbarProps = {
  currentPage: Page
}

export function Navbar({ currentPage }: NavbarProps) {
  return (
    <header className="navbar-wrap">
      <nav className="navbar" aria-label="Navegação principal">
        <a className="brand" href="#/" aria-label="Diário de Bordo - Início">
          <span className="brand-mark" aria-hidden="true">DB</span>
          <span className="brand-name">Diário de Bordo</span>
        </a>

        <div className="nav-links">
          {navItems.map((item) => (
            <a
              className={currentPage === item.page ? 'nav-link active' : 'nav-link'}
              href={item.href}
              key={item.page}
              aria-current={currentPage === item.page ? 'page' : undefined}
            >
              {item.label}
            </a>
          ))}
        </div>
      </nav>
    </header>
  )
}
