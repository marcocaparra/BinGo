# BinGo

O BinGo transforma o descarte de resíduos eletrônicos em uma experiência gamificada para escolas. Este repositório reúne o totem, o aplicativo, os serviços de apoio, o banco e as ferramentas internas do projeto.

## Estado do repositório

Esta é a branch principal de integração do projeto. Todo trabalho novo deve partir da `main` e voltar para ela por Pull Request.

| Frente | Situação | Local |
| --- | --- | --- |
| Diário de Bordo | Versão estável publicada | `Software/tools/diario-bordo` |
| Totem kiosk | Protótipo visual em evolução | `Software/apps/totem_kiosk_wireframe` |
| App mobile | Aplicativo Flutter em evolução | `Software/mobile/bingo_app` |
| Backend principal | FastAPI temporário | `Software/backend` |
| Backend alvo | Supabase e Edge Functions | `Software/supabase` |
| Visão computacional | Protótipos e modelos | `Hardware/BinGoVision` |

O backend FastAPI preserva regras e contratos importantes do MVP, mas a direção técnica aprovada para o produto é Supabase PostgreSQL com Edge Functions em Deno/TypeScript.

## Mapa rápido

```text
BinGo/
|-- Hardware/
|   `-- BinGoVision/
|-- Software/
|   |-- apps/
|   |   |-- totem_kiosk_wireframe/
|   |   `-- totem_simulator/
|   |-- backend/
|   |-- database/
|   |-- docs/
|   |-- mobile/bingo_app/
|   |-- supabase/
|   `-- tools/diario-bordo/
|-- assets/
`-- README.md
```

## Onde mexer

| Necessidade | Comece por |
| --- | --- |
| Diário de Bordo | `Software/tools/diario-bordo` |
| Fluxo visual do totem | `Software/apps/totem_kiosk_wireframe` |
| Simulação de depósito e ranking | `Software/apps/totem_simulator` |
| Regras temporárias do backend | `Software/backend/src/domain` |
| Banco e dados de demonstração | `Software/database` e `Software/supabase` |
| Aplicativo Flutter | `Software/mobile/bingo_app` |
| Visão computacional | `Hardware/BinGoVision` |

## Branches

| Branch | Uso |
| --- | --- |
| `main` | Integração atual e origem de todo trabalho novo |
| `legacy` | Arquitetura antiga preservada apenas para consulta |
| `release/diario-bordo-v0` | Fonte do serviço publicado do Diário de Bordo |
| `feature/totem-v1` | Evolução ainda em revisão do totem |
| `feature/mobile-pin-refresh` | Evolução ainda em revisão do aplicativo |

A `legacy` não deve receber novas funcionalidades. A branch de release existe porque o serviço publicado acompanha esse nome; mudanças normais do Diário continuam partindo da `main`.

## Fluxo de contribuição

```text
main -> feature/fix/docs -> commits -> Pull Request -> revisão -> main
```

1. Atualize a `main`.
2. Crie uma branch com escopo claro.
3. Faça commits pequenos e relacionados.
4. Abra um Pull Request para `main`.
5. Registre os testes executados.
6. Exclua a branch depois do merge.

O padrão de commit é:

```text
tipo(escopo): descrição curta
```

Exemplos:

```text
feat(totem): add disposal confirmation flow
fix(diario-bordo): prevent future report dates
docs(repo): clarify branch workflow
test(mobile): cover PIN validation
```

O modelo completo de branches, commits e Pull Requests está em [Software/docs/github-workflow.md](Software/docs/github-workflow.md).

## Execução local

Cada frente possui dependências próprias. Consulte seu README antes de iniciar.

### Diário de Bordo

```powershell
cd Software/tools/diario-bordo
docker compose up --build
```

### Totem visual

```powershell
cd Software
python -m http.server 8092 --bind 127.0.0.1
```

Abra `http://127.0.0.1:8092/apps/totem_kiosk_wireframe/`.

### App Flutter

```powershell
cd Software/mobile/bingo_app
flutter pub get
flutter analyze
flutter test
```

## Decisões preservadas

- O totem V1 é web/kiosk.
- O aplicativo Flutter V1 é voltado para consulta.
- O resgate acontece no totem físico.
- O backend final segue a direção Supabase e Edge Functions.
- Credenciais, arquivos `.env`, bancos locais, builds e evidências enviadas não devem ser versionados.

## Licença

Consulte [LICENSE](LICENSE).
