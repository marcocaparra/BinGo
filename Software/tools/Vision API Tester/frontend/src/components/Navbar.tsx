import type { AppRoute } from "../App";

interface NavbarProps {
  activeRoute: AppRoute;
  onNavigate: (route: AppRoute) => void;
}

const navItems: Array<{ label: string; route: AppRoute }> = [
  { label: "Dashboard", route: "/dashboard" },
  { label: "Novo Teste", route: "/new-test" },
  { label: "Histórico", route: "/history" }
];

export function Navbar({ activeRoute, onNavigate }: NavbarProps) {
  return (
    <header className="topbar">
      <button className="brand" type="button" onClick={() => onNavigate("/dashboard")}>
        <span className="brand-mark" aria-hidden="true" />
        <span>
          <strong>Vision API Tester</strong>
          <small>Computer vision lab</small>
        </span>
      </button>

      <nav className="nav-actions" aria-label="Navegação principal">
        {navItems.map((item) => (
          <button
            className={`nav-button ${activeRoute === item.route ? "is-active" : ""}`}
            key={item.route}
            type="button"
            onClick={() => onNavigate(item.route)}
          >
            {item.label}
          </button>
        ))}
      </nav>
    </header>
  );
}
