# Frontend do Diário de Bordo Coletivo

Frontend React da ferramenta interna do projeto BinGo. Integrantes e relatórios
são carregados da API Spring Boot; autenticação, pendências automáticas e
exportação permanecem fora desta etapa.

## Configuração

Crie um arquivo `.env` nesta pasta usando `.env.example` como base:

```env
VITE_API_BASE_URL=http://localhost:8080
```

Reinicie o Vite sempre que alterar variáveis de ambiente.

## Executar localmente

Com o backend em execução:

```bash
npm install
npm run dev
```

O frontend normalmente ficará disponível em `http://localhost:5173`.

## Verificações

```bash
npm run lint
npm run build
```

## Integração atual

- `GET /members`: integrantes do formulário;
- `GET /reports`: histórico;
- `POST /reports/today`: envio do relatório diário;
- `POST /reports/no-activity`: registro de dia sem atividade.

O backend local permite requisições de `http://localhost:5173` e
`http://127.0.0.1:5173`. Outros ambientes podem definir as origens permitidas
pela variável `CORS_ALLOWED_ORIGINS`.
