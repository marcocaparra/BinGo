interface LucideRuntime {
  createIcons(options?: { attrs?: Record<string, string | number> }): void;
}

interface Window {
  lucide?: LucideRuntime;
}
