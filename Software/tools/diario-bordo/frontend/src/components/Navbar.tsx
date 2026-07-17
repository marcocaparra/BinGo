import type { Page } from '../App'
import type { AuthRole } from '../types/auth'

type IconName = 'chart' | 'history' | 'logout' | 'note' | 'rocket' | 'team'

type NavItem = {
  label: string
  page: Page
  href: string
  helper?: string
  icon: IconName
}

type SidebarProps = {
  collapsed: boolean
  currentPage: Page
  role: AuthRole
  onLogout: () => void
  onNavigate: () => void
  onToggleCollapse: () => void
}

const teamGroups: Array<{ title: string; items: NavItem[] }> = [
  {
    title: 'Registro',
    items: [
      { label: 'Registro do dia', page: 'today', href: '#/hoje', helper: 'Preencher diário', icon: 'note' },
    ],
  },
]

const adminGroups: Array<{ title: string; items: NavItem[] }> = [
  {
    title: 'Consolidação',
    items: [
      { label: 'Painel', page: 'export', href: '#/exportar', helper: 'Resumo e Markdown', icon: 'chart' },
      { label: 'Histórico', page: 'history', href: '#/historico', helper: 'Registros e edição', icon: 'history' },
    ],
  },
  {
    title: 'Registro',
    items: [
      { label: 'Preencher', page: 'today', href: '#/hoje', helper: 'Meu diário do dia', icon: 'note' },
    ],
  },
]

function SidebarIcon({ icon }: { icon: IconName }) {
  return (
    <svg className="app-sidebar-svg" aria-hidden="true" viewBox="0 0 24 24">
      {icon === 'chart' && (
        <>
          <path d="M5 19V9" />
          <path d="M12 19V5" />
          <path d="M19 19v-7" />
          <path d="M4 19h16" />
        </>
      )}
      {icon === 'history' && (
        <>
          <path d="M5 6h14" />
          <path d="M5 12h14" />
          <path d="M5 18h9" />
          <path d="M4 4v16" />
        </>
      )}
      {icon === 'note' && (
        <>
          <path d="M7 4h8l3 3v13H7z" />
          <path d="M14 4v4h4" />
          <path d="M9 12h6" />
          <path d="M9 16h4" />
        </>
      )}
      {icon === 'rocket' && (
        <>
          <path d="M14 4c3.2.5 5.5 2.8 6 6l-5 5-6-6z" />
          <path d="M9 9 5.5 10.5 4 15l4.5-1.5" />
          <path d="M15 15 13.5 19 9 20l1.5-3.5" />
          <path d="M15 8h.01" />
        </>
      )}
      {icon === 'team' && (
        <>
          <path d="M8 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z" />
          <path d="M16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z" />
          <path d="M3.5 19c.7-3 2.5-4.5 4.5-4.5s3.8 1.5 4.5 4.5" />
          <path d="M11.5 19c.7-3 2.5-4.5 4.5-4.5 1.7 0 3.3 1.1 4.1 3.3" />
        </>
      )}
      {icon === 'logout' && (
        <>
          <path d="M10 6H6v12h4" />
          <path d="M14 8l4 4-4 4" />
          <path d="M18 12H9" />
        </>
      )}
    </svg>
  )
}

export function AppSidebar({
  collapsed,
  currentPage,
  role,
  onLogout,
  onNavigate,
  onToggleCollapse,
}: SidebarProps) {
  const groups = role === 'ADMIN' ? adminGroups : teamGroups
  const profileLabel = role === 'ADMIN' ? 'Coordenação' : 'Equipe'
  const profileHelper = role === 'ADMIN' ? 'Acesso ativo' : 'Registro ativo'
  const profileIcon: IconName = role === 'ADMIN' ? 'rocket' : 'team'

  return (
    <aside
      className={`app-sidebar ${collapsed ? 'collapsed' : ''} ${role === 'TEAM' ? 'team-sidebar' : 'admin-sidebar'}`}
      aria-label={role === 'ADMIN' ? 'Navegação da coordenação' : 'Navegação da equipe'}
    >
      <div className="app-sidebar-header">
        <a
          className="app-sidebar-brand"
          href={role === 'ADMIN' ? '#/exportar' : '#/hoje'}
          aria-label="BinGo Diário de Bordo"
          onClick={onNavigate}
        >
          <span className="brand-mark" aria-hidden="true">
            <img src="/bingo-logo.png" alt="" />
          </span>
          <span className="sidebar-copy">
            <strong>BinGo</strong>
            <small>Diário de Bordo</small>
          </span>
        </a>
        <button
          className="sidebar-collapse-button"
          type="button"
          onClick={onToggleCollapse}
          aria-expanded={!collapsed}
          aria-label={collapsed ? 'Expandir navegação' : 'Recolher navegação'}
          title={collapsed ? 'Expandir navegação' : 'Recolher navegação'}
        >
          <svg className="sidebar-toggle-icon desktop-toggle-icon" aria-hidden="true" viewBox="0 0 24 24">
            <path d="M9 6l6 6-6 6" />
          </svg>
          <svg className="sidebar-toggle-icon mobile-menu-icon" aria-hidden="true" viewBox="0 0 24 24">
            <path d="M4 7h16" />
            <path d="M4 12h16" />
            <path d="M4 17h16" />
          </svg>
          <svg className="sidebar-toggle-icon mobile-close-icon" aria-hidden="true" viewBox="0 0 24 24">
            <path d="M6 6l12 12" />
            <path d="M18 6 6 18" />
          </svg>
        </button>
      </div>

      <nav className="app-sidebar-nav">
        {groups.map((group) => (
          <section className="app-sidebar-group" key={group.title}>
            <p className="app-sidebar-section-title">{group.title}</p>
            <div className="app-sidebar-items">
              {group.items.map((item) => (
                <a
                  className={currentPage === item.page ? 'app-sidebar-item active' : 'app-sidebar-item'}
                  href={item.href}
                  key={item.page}
                  aria-current={currentPage === item.page ? 'page' : undefined}
                  onClick={onNavigate}
                  title={collapsed ? item.label : undefined}
                >
                  <span className="app-sidebar-icon" aria-hidden="true">
                    <SidebarIcon icon={item.icon} />
                  </span>
                  <span className="sidebar-copy">
                    <strong>{item.label}</strong>
                    {item.helper && <small>{item.helper}</small>}
                  </span>
                </a>
              ))}
            </div>
          </section>
        ))}
      </nav>

      <div className="app-sidebar-footer">
        <div className="app-profile-card">
          <span className="app-sidebar-icon" aria-hidden="true">
            <SidebarIcon icon={profileIcon} />
          </span>
          <span className="sidebar-copy">
            <strong>{profileLabel}</strong>
            <small>{profileHelper}</small>
          </span>
        </div>
        <button className="app-logout-button" type="button" onClick={onLogout}>
          <span className="app-sidebar-icon" aria-hidden="true">
            <SidebarIcon icon="logout" />
          </span>
          <span className="sidebar-copy">Sair do acesso</span>
        </button>
      </div>
    </aside>
  )
}
