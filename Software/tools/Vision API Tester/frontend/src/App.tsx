import { useEffect, useMemo, useState } from "react";
import { Navbar } from "./components/Navbar";
import { DashboardPage } from "./pages/DashboardPage";
import { HistoryPage } from "./pages/HistoryPage";
import { NewTestPage } from "./pages/NewTestPage";

export type AppRoute = "/dashboard" | "/new-test" | "/history";

const routeSet = new Set<AppRoute>(["/dashboard", "/new-test", "/history"]);

function normalizePath(pathname: string): AppRoute {
  if (pathname === "/") {
    return "/dashboard";
  }

  return routeSet.has(pathname as AppRoute) ? (pathname as AppRoute) : "/dashboard";
}

export default function App() {
  const [activeRoute, setActiveRoute] = useState<AppRoute>(() => normalizePath(window.location.pathname));

  useEffect(() => {
    if (window.location.pathname === "/") {
      window.history.replaceState({}, "", "/dashboard");
    }

    const handlePopState = () => setActiveRoute(normalizePath(window.location.pathname));
    window.addEventListener("popstate", handlePopState);

    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  const CurrentPage = useMemo(() => {
    if (activeRoute === "/new-test") {
      return NewTestPage;
    }

    if (activeRoute === "/history") {
      return HistoryPage;
    }

    return DashboardPage;
  }, [activeRoute]);

  function navigate(route: AppRoute) {
    window.history.pushState({}, "", route);
    setActiveRoute(route);
  }

  return (
    <>
      <Navbar activeRoute={activeRoute} onNavigate={navigate} />
      <main className="app-shell">
        <CurrentPage />
      </main>
    </>
  );
}
