# Frontend do Diário de Bordo Coletivo

V0 visual e navegável da ferramenta interna do projeto BinGo. Esta versão usa
somente dados mockados e estado local: não há autenticação, backend, banco de
dados ou exportação real.

## Tecnologias

- Vite;
- React;
- TypeScript;
- CSS puro.

## Executar localmente

```bash
npm install
npm run dev
```

O Vite exibirá o endereço local no terminal, normalmente
`http://localhost:5173`.

## Verificações

```bash
npm run lint
npm run build
```

## Páginas

- Início;
- Relatório de hoje;
- Histórico com filtros locais;
- Relatórios pendentes;
- Exportação futura.

Os dados de demonstração ficam em `src/data/mockData.ts`.
