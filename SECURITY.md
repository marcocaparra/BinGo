# Política de segurança

## Escopo suportado

| Linha | Suporte |
| --- | --- |
| `develop` | Ativa, recebe correções |
| `release/diario-bordo-v0` | Correções deliberadas do serviço publicado |
| `main` | Legado, somente consulta |

## Como registrar uma vulnerabilidade

Não publique segredos, credenciais, PINs reais ou dados pessoais em issues e Pull Requests.

1. Avise Marco pelo canal interno da equipe.
2. Registre uma issue privada ou um Security Advisory no repositório com evidência mínima.
3. Informe componente afetado, impacto, forma de reprodução e commit conhecido.
4. Não explore a falha em dados reais nem compartilhe credenciais na evidência.

## Tratamento

- Falha crítica de autenticação, exposição de dados ou credencial vazada deve ser triada antes de novas features.
- A correção deve ocorrer em branch isolada, com teste de regressão e revisão de outra pessoa.
- Segredos expostos devem ser revogados e substituídos; removê-los apenas do commit mais recente não é suficiente.
- Dependências vulneráveis devem ser atualizadas em PR próprio, sem mudanças funcionais não relacionadas.

## Controles atuais

- Alertas de vulnerabilidade do GitHub devem permanecer ativos.
- Workflows devem usar permissões mínimas.
- Segredos de Actions devem ficar em GitHub Secrets.
- Código de produto não deve depender de credenciais padrão ou previsíveis.
