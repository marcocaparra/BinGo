# Como contribuir com o BinGo

Este repositório é privado e usado pela equipe do BinGo. O objetivo destas regras é preservar o trabalho de cada frente e tornar Pull Requests fáceis de entender.

## Branches

- `develop` é a branch padrão e a linha ativa de integração.
- `main` preserva o legado e não recebe desenvolvimento novo.
- Todo trabalho parte da `develop` em uma branch própria.
- Use `feature/`, `fix/`, `docs/`, `ci/`, `chore/` ou `hotfix/` conforme o objetivo.
- Não faça force push em branch compartilhada.
- Não exclua uma branch sem confirmação explícita do responsável.

## Pull Requests

Um PR deve representar uma única frente ou alteração lógica. Não misture mobile, totem, backend e documentação sem necessidade técnica.

Abra como rascunho enquanto houver código incompleto, teste pendente ou decisão aberta. Para marcar como pronto:

1. preencha o template;
2. execute os checks aplicáveis;
3. solicite o responsável indicado pelo `CODEOWNERS`;
4. resolva comentários bloqueantes;
5. atualize a branch com `develop`.

PRs grandes devem ser revisados por blocos claros. Quando for possível dividir sem reescrever histórico ou perder trabalho, prefira PRs menores.

## Responsáveis técnicos

| Área | Revisão principal |
| --- | --- |
| Produto, integração e governança | `@marcocaparra` |
| Backend, banco, Supabase e Diário | `@vpredeus` |
| Totem, Flutter e experiência visual | `@gugdev` |

Uma pessoa não deve aprovar sozinha uma mudança crítica que ela própria implementou. Mudanças em autenticação, migrations, produção ou dados exigem revisão adicional.

## Commits

Use o formato:

```text
tipo(escopo): descrição curta
```

Exemplos:

```text
feat(totem): add disposal confirmation
fix(backend): reject invalid machine key
test(mobile): cover PIN validation
docs(repo): clarify review workflow
ci(mobile): run Flutter checks
```

Evite mensagens vagas como `update`, `mudanças`, `teste` ou `arrumando`.

## Segurança

- Nunca versione `.env`, tokens, credenciais, PINs reais ou dados pessoais.
- Use GitHub Secrets para valores usados em Actions.
- Logs e screenshots devem ocultar dados sensíveis.
- Dependências vulneráveis e falhas de autenticação devem ser registradas com a label `security`.

## Antes do merge

- checks aplicáveis verdes;
- revisão técnica registrada;
- risco e pendências documentados;
- nenhuma alteração não relacionada no diff;
- nenhuma branch ou código de outra frente removidos.
