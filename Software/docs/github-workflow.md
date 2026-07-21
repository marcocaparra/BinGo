# Organização do GitHub - BinGo

## Objetivo

Este documento define o fluxo oficial de branches, commits e Pull Requests do BinGo. A meta é manter uma única linha atual do projeto, preservar o histórico antigo sem confundi-lo com desenvolvimento ativo e permitir que cada frente avance isoladamente.

## Branches permanentes

### `main`

É a branch principal e padrão do repositório.

- Todo trabalho novo parte dela.
- Toda integração volta para ela por Pull Request.
- Não recebe desenvolvimento direto nem force push.
- Deve permanecer executável e com os testes aplicáveis aprovados.

### `legacy`

Preserva a arquitetura que antes ocupava a antiga `main`.

- Serve apenas para consulta e recuperação histórica.
- Não recebe novas funcionalidades.
- Uma correção que ainda seja útil deve ser reaplicada na `main`, não desenvolvida aqui.

### `release/diario-bordo-v0`

É a fonte acompanhada pelo ambiente publicado do Diário de Bordo.

- Recebe apenas promoções ou correções deliberadas do Diário.
- Não substitui a `main` como origem de trabalho.
- Deve permanecer enquanto o provedor de hospedagem estiver conectado a ela.

## Branches de trabalho

| Prefixo | Uso | Exemplo |
| --- | --- | --- |
| `feature/` | Nova funcionalidade | `feature/totem-v1` |
| `fix/` | Correção pontual | `fix/diario-auth` |
| `docs/` | Apenas documentação | `docs/api-contract` |
| `hotfix/` | Correção urgente de produção | `hotfix/diario-login` |

Cada branch deve representar uma frente clara. Totem, mobile e Diário não devem dividir a mesma branch quando as alterações puderem ser revisadas separadamente.

## Fluxo oficial

```text
main
  -> feature/fix/docs/hotfix
  -> commits
  -> push
  -> Pull Request para main
  -> revisão e testes
  -> merge
  -> exclusão da branch concluída
```

Use PR em rascunho quando a interface ou a lógica ainda estiver em construção. Marque-o como pronto somente quando o escopo estiver completo e os testes relevantes tiverem sido executados.

## Commits

Use Conventional Commits com escopo quando ele ajudar a localizar a mudança:

```text
tipo(escopo): descrição curta
```

Tipos usuais: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `build`, `ci` e `seed`.

Exemplos:

```text
feat(totem): add disposal confirmation flow
fix(diario-bordo): show no-activity records in history
docs(repo): clarify main branch workflow
test(mobile): cover PIN validation
```

Cada commit deve representar uma alteração lógica. Evite mensagens vagas como `update`, `alterações`, `teste` ou `corrigindo`.

## Pull Requests

O título deve resumir o resultado, preferencialmente no mesmo formato dos commits. A descrição deve conter:

```markdown
## Objetivo

Explique o resultado entregue.

## Alterações

- Liste as mudanças relevantes.

## Testes

- [x] Informe testes automatizados, lint, build e validações manuais.

## Observações

Registre migrations, variáveis de ambiente, dependências e riscos conhecidos.
```

Antes do merge:

- atualize a branch com a `main`;
- resolva conflitos sem apagar trabalho de outras frentes;
- confirme que arquivos locais, segredos e builds não entraram no commit;
- obtenha revisão de outra pessoa quando a mudança afetar produção;
- confirme os checks do GitHub.

## Regras de segurança do histórico

- Não fazer force push em branches compartilhadas.
- Não reescrever ou apagar commits de outras pessoas.
- Não desenvolver diretamente na `main`.
- Não misturar uma atualização de README com código sem relação.
- Não excluir `legacy` nem `release/diario-bordo-v0` sem confirmar dependências externas.
- Excluir branches de feature apenas depois de confirmar que foram integradas.

Documentos históricos podem citar a antiga `develop`; isso registra o contexto da época e não altera o fluxo atual.
