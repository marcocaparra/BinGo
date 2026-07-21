# Contrato de Dados - Totem, App e Backend

Status: alinhamento V1

## Objetivo

Evitar divergencia entre Totem, App e Backend definindo quais dados cada frente precisa mostrar, enviar, receber, mockar ou simular no V1.

Este contrato deve ser usado antes de criar telas, mocks ou integracoes. Nenhuma tela deve inventar nomes, saldos, rankings, recompensas, historicos ou estados diferentes dos dados definidos aqui.

## Decisoes de Fonte

Decisoes_de_Fonte:
- Dado: Escola
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: Usada para contexto do Totem e filtro de recompensas.
- Dado: Maquina/Totem
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: Autenticada por `X-Machine-Id` e `X-Api-Key`.
- Dado: Aluno
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: `students` e a fonte de dominio para nome, turma, saldo e status.
- Dado: PIN do Totem
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: Nunca trafegar ou salvar PIN em texto puro fora do fluxo necessario. Backend armazena `pin_hash`.
- Dado: Turma, serie e segmento
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: Vem de `classes.name`, `classes.grade` e `classes.segment`.
- Dado: Saldo individual
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: `students.points_student_balance`.
- Dado: Saldo da turma
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: `classes.points_class_balance`.
- Dado: Deposito/descarte
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: O simulador pode escolher tipo/tamanho/validade, mas o Backend registra o evento.
- Dado: IA de classificacao
  - Fonte de verdade V1: Totem/simulador
  - Status V1: Mockado
  - Observacao: No V1, `detected_type`, `size` e `is_valid` podem ser definidos pelo simulador.
- Dado: Pontos gerados
  - Fonte de verdade V1: Backend
  - Status V1: Real
  - Observacao: Calculados pelo Backend a partir de regras da escola e tamanho do item.
- Dado: Ranking do Totem
  - Fonte de verdade V1: Backend
  - Status V1: Real
  - Observacao: Disponivel em `/v1/totem/rankings`.
- Dado: Ranking do App
  - Fonte de verdade V1: Backend a criar
  - Status V1: Mockado
  - Observacao: Deve usar mesma unidade `Bins` e mesma ordenacao definida neste contrato.
- Dado: Recompensas
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: Disponivel em `/v1/rewards?school_id=...`.
- Dado: Resgate
  - Fonte de verdade V1: Backend/Banco
  - Status V1: Real
  - Observacao: Endpoint existe em `/v1/redemptions`, mas canal atual do dominio e `TOTEM`.
- Dado: Missoes
  - Fonte de verdade V1: Produto/App
  - Status V1: Mockado
  - Observacao: Nao ha entidade ou endpoint de missoes no Backend V1 atual.
- Dado: Impacto ambiental
  - Fonte de verdade V1: Produto/App
  - Status V1: Mockado
  - Observacao: Pode ser exibido apenas com formula combinada e identificada como mock/demo.
- Dado: Reset
  - Fonte de verdade V1: Totem/Backend/Admin
  - Status V1: Mockado
  - Observacao: Nao ha endpoint especifico de reset no contrato atual.


## Totem - Dados Minimos

Totem_Dados_Minimos:
- Necessidade: Identificar escola
  - Campo/Contrato: `school.id`, `school.name`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context`
  - Regra de exibicao: Mostrar nome da escola carregada; se falhar, estado de erro.
- Necessidade: Identificar maquina
  - Campo/Contrato: `machine.id`, `machine.name`, `machine.status`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context`
  - Regra de exibicao: Status permitido: `ONLINE`, `OFFLINE`, `MAINTENANCE`, `OUT_OF_SERVICE`.
- Necessidade: Listar aluno
  - Campo/Contrato: `student.id`, `student.name`, `student.status`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context`
  - Regra de exibicao: Exibir somente alunos retornados pelo backend.
- Necessidade: Mostrar turma
  - Campo/Contrato: `student.class_id`, `student.class_name`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context`
  - Regra de exibicao: Nao criar turma manual na tela.
- Necessidade: Mostrar serie
  - Campo/Contrato: `class.grade`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context`
  - Regra de exibicao: Usar valor cadastrado na turma.
- Necessidade: Mostrar segmento
  - Campo/Contrato: `class.segment`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context`
  - Regra de exibicao: Usar valor cadastrado na turma.
- Necessidade: PIN
  - Campo/Contrato: PIN digitado, `pin_hash` no banco
  - Direcao: Totem -> Backend
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: Fluxo de autenticacao por PIN
  - Regra de exibicao: O Totem nao deve persistir PIN em texto puro.
- Necessidade: Status da sessao
  - Campo/Contrato: `idle`, `student_selected`, `depositing`, `success`, `error`, `resetting`
  - Direcao: Local Totem
  - Fonte: Totem
  - Status V1: Simulado/Real de UI
  - Endpoint/Origem: Estado local
  - Regra de exibicao: Estados padrao para todas as telas do Totem.
- Necessidade: Item aceito/recusado
  - Campo/Contrato: `is_valid: boolean`
  - Direcao: Totem -> Backend
  - Fonte: Totem/simulador
  - Status V1: Simulado
  - Endpoint/Origem: `POST /v1/deposits`
  - Regra de exibicao: Aceito gera pontos conforme Backend; recusado gera 0 pontos.
- Necessidade: Categoria/tipo do item
  - Campo/Contrato: `detected_type`
  - Direcao: Totem -> Backend
  - Fonte: Totem/simulador
  - Status V1: Simulado
  - Endpoint/Origem: `POST /v1/deposits`
  - Regra de exibicao: Valores demo podem ser `mouse`, `pilha`, `teclado`, `cabo`, `carregador`; manter string simples.
- Necessidade: Tamanho do item
  - Campo/Contrato: `size`
  - Direcao: Totem -> Backend
  - Fonte: Totem/simulador
  - Status V1: Simulado
  - Endpoint/Origem: `POST /v1/deposits`
  - Regra de exibicao: Valores oficiais: `SMALL`, `MEDIUM`, `LARGE`.
- Necessidade: IA simulada
  - Campo/Contrato: `detected_type`, `size`, `is_valid`, `confidence`
  - Direcao: Local/Totem -> Backend parcial
  - Fonte: Totem/simulador
  - Status V1: Simulado
  - Endpoint/Origem: Simulador ou Edge local
  - Regra de exibicao: `confidence` nao deve ser enviado ao Backend ate contrato existir.
- Necessidade: Pontos do descarte
  - Campo/Contrato: `points_awarded_student`, `points_awarded_class`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: Resposta `POST /v1/deposits`
  - Regra de exibicao: Nunca calcular na tela como fonte final.
- Necessidade: Saldo individual
  - Campo/Contrato: `points_student_balance`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context` ou summary
  - Regra de exibicao: Atualizar apos deposito recarregando dados reais.
- Necessidade: Saldo da turma
  - Campo/Contrato: `points_class_balance`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/context`
  - Regra de exibicao: Atualizar apos deposito recarregando dados reais.
- Necessidade: Ranking alunos
  - Campo/Contrato: `students[].name`, `class_name`, `points_student_balance`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/rankings`
  - Regra de exibicao: Ordenacao definida pelo Backend.
- Necessidade: Ranking turmas
  - Campo/Contrato: `classes[].name`, `points_class_balance`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/rankings`
  - Regra de exibicao: Ordenacao definida pelo Backend.
- Necessidade: Historico recente
  - Campo/Contrato: `recent_deposits[]`
  - Direcao: Backend -> Totem
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/totem/students/{student_id}/summary`
  - Regra de exibicao: Usar somente eventos retornados.
- Necessidade: Erro
  - Campo/Contrato: `detail` ou mensagem padrao
  - Direcao: Backend -> Totem
  - Fonte: Backend/UI
  - Status V1: Real de UI
  - Endpoint/Origem: Qualquer endpoint
  - Regra de exibicao: Exibir mensagem curta e acao de tentar novamente.
- Necessidade: Reset
  - Campo/Contrato: limpar aluno selecionado, limpar mensagem, voltar a `idle`
  - Direcao: Local Totem
  - Fonte: Totem
  - Status V1: Mockado/Real de UI
  - Endpoint/Origem: Estado local
  - Regra de exibicao: Reset de PIN ou dados no Backend entra depois.

### Payload oficial do Totem para deposito

```json
{
  "event_id": "uuid",
  "class_id": "uuid",
  "student_id": "uuid-ou-null",
  "is_valid": true,
  "detected_type": "mouse",
  "size": "SMALL"
}
```

Headers obrigatorios do Totem/Edge:

Payload_oficial_do_Totem_para_deposito:
- Header: `X-Machine-Id`
  - Obrigatorio: Sim
  - Observacao: Identifica a maquina cadastrada.
- Header: `X-Api-Key`
  - Obrigatorio: Sim
  - Observacao: Credencial tecnica do Totem/Edge.

## App - Dados Minimos

App_Dados_Minimos:
- Necessidade: Perfil
  - Campo/Contrato: `id`, `name`, `school_id`, `class_id`
  - Direcao: Backend -> App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/me/profile`
  - Regra de exibicao: Usar o aluno autenticado.
- Necessidade: Saldo individual
  - Campo/Contrato: `points_student_balance`
  - Direcao: Backend -> App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/me/profile`
  - Regra de exibicao: Unidade visual: `Bins`.
- Necessidade: Saldo da turma
  - Campo/Contrato: `points_class_balance`
  - Direcao: Backend -> App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/me/profile`
  - Regra de exibicao: Usar como dado coletivo da turma.
- Necessidade: Historico de descartes
  - Campo/Contrato: `event_id`, `is_valid`, `detected_type`, `points_awarded_student`, `points_awarded_class`, `created_at`
  - Direcao: Backend -> App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/me/deposits`
  - Regra de exibicao: Lista cronologica definida pelo Backend.
- Necessidade: Historico de resgates
  - Campo/Contrato: `id`, `code`, `status`, `created_at`
  - Direcao: Backend -> App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/me/redemptions`
  - Regra de exibicao: Status: `PENDING`, `DELIVERED`, `CANCELED`, `EXPIRED`.
- Necessidade: Ranking
  - Campo/Contrato: `position`, `name`, `class_name`, `points_student_balance`
  - Direcao: Backend -> App
  - Fonte: Backend
  - Status V1: Mockado ate endpoint
  - Endpoint/Origem: Reutilizar contrato de Totem ou criar `/v1/me/rankings`
  - Regra de exibicao: Enquanto mockado, usar dados fixos padronizados, nao aleatorios.
- Necessidade: Missoes
  - Campo/Contrato: `id`, `title`, `description`, `progress`, `target`, `reward_bins`, `status`
  - Direcao: App/Produto
  - Fonte: App
  - Status V1: Mockado
  - Endpoint/Origem: Fixture padrao
  - Regra de exibicao: Nao existe endpoint ou tabela V1.
- Necessidade: Recompensas
  - Campo/Contrato: `id`, `name`, `description`, `cost_points`, `category`, `status`, `stock_qty`
  - Direcao: Backend -> App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/rewards?school_id=...`
  - Regra de exibicao: Mostrar apenas recompensas retornadas.
- Necessidade: Impacto
  - Campo/Contrato: `total_items`, `valid_items`, `bins_generated`, `impact_text`
  - Direcao: App/Produto
  - Fonte: App/Backend parcial
  - Status V1: Mockado
  - Endpoint/Origem: Derivado de historico ou fixture
  - Regra de exibicao: Nao inventar conversoes ambientais como dado real.
- Necessidade: Resgate
  - Campo/Contrato: `reward_id` para criar; resposta com `id`, `code`, `status`, datas
  - Direcao: App -> Backend -> App
  - Fonte: Backend
  - Status V1: Real tecnicamente, validar canal de produto
  - Endpoint/Origem: `POST /v1/redemptions`
  - Regra de exibicao: Backend atual registra `request_channel = TOTEM`; confirmar se App pode criar no V1 antes de liberar UI.
- Necessidade: Estado vazio - perfil
  - Campo/Contrato: sem usuario autenticado
  - Direcao: App
  - Fonte: App
  - Status V1: Real de UI
  - Endpoint/Origem: Estado local
  - Regra de exibicao: Mostrar acao de login.
- Necessidade: Estado vazio - historico
  - Campo/Contrato: lista vazia
  - Direcao: Backend/App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/me/deposits`
  - Regra de exibicao: Texto padrao: sem descartes registrados.
- Necessidade: Estado vazio - recompensas
  - Campo/Contrato: lista vazia
  - Direcao: Backend/App
  - Fonte: Backend
  - Status V1: Real
  - Endpoint/Origem: `GET /v1/rewards`
  - Regra de exibicao: Texto padrao: sem recompensas disponiveis.
- Necessidade: Estado vazio - ranking
  - Campo/Contrato: lista vazia ou indisponivel
  - Direcao: App
  - Fonte: App
  - Status V1: Real de UI
  - Endpoint/Origem: Estado local
  - Regra de exibicao: Nao preencher com pessoas aleatorias.
- Necessidade: Erro
  - Campo/Contrato: `detail` ou mensagem padrao
  - Direcao: Backend -> App
  - Fonte: Backend/UI
  - Status V1: Real de UI
  - Endpoint/Origem: Qualquer endpoint
  - Regra de exibicao: Exibir mensagem curta e permitir tentar novamente.
- Necessidade: Carregamento
  - Campo/Contrato: `loading` por secao
  - Direcao: App
  - Fonte: App
  - Status V1: Real de UI
  - Endpoint/Origem: Estado local
  - Regra de exibicao: Skeleton/spinner sem dados falsos.

### Fixture padrao permitida para App enquanto mockado

Usar apenas quando a tela ainda nao estiver integrada. Deve ficar centralizada em um unico arquivo de mock do App.

Fixture_padrao_permitida_para_App_enquanto_mockado:
- Area: Moeda
  - Valor padrao: `Bins`
- Area: Missoes
  - Valor padrao: `Levar 3 itens validos`, `Completar 1 descarte medio`, `Ajudar a turma a subir no ranking`
- Area: Ranking App
  - Valor padrao: Usar nomes de alunos/turmas vindos de seed/demo oficial quando disponivel; se nao houver, mostrar estado indisponivel.
- Area: Impacto
  - Valor padrao: Texto generico sem numero ambiental real: `Impacto em calculo para o piloto`.

## Backend - Contratos Minimos

Backend_Contratos_Minimos:
- Area: Contexto do Totem
  - Endpoint/Entidade: `GET /v1/totem/context`
  - Envia: Escola, maquina, turmas, alunos
  - Recebe: Headers da maquina
  - Status V1: Real
  - Responsabilidade: Retornar dados autorizados para a maquina/escola.
- Area: Resumo do aluno no Totem
  - Endpoint/Entidade: `GET /v1/totem/students/{student_id}/summary`
  - Envia: Aluno, estatisticas, depositos recentes
  - Recebe: `student_id`, headers
  - Status V1: Real
  - Responsabilidade: Consolidar historico recente e contadores.
- Area: Ranking do Totem
  - Endpoint/Entidade: `GET /v1/totem/rankings`
  - Envia: Ranking de alunos e turmas
  - Recebe: Headers da maquina
  - Status V1: Real
  - Responsabilidade: Ordenar ranking de forma consistente.
- Area: Registro de deposito
  - Endpoint/Entidade: `POST /v1/deposits` ou `/v1/deposits/sync`
  - Envia: Pontos gerados e data
  - Recebe: Evento de deposito
  - Status V1: Real
  - Responsabilidade: Validar maquina, turma, aluno, idempotencia e calcular pontos.
- Area: Perfil do App
  - Endpoint/Entidade: `GET /v1/me/profile`
  - Envia: Perfil e saldos
  - Recebe: Token do aluno
  - Status V1: Real
  - Responsabilidade: Retornar dados do aluno autenticado.
- Area: Historico do App
  - Endpoint/Entidade: `GET /v1/me/deposits`
  - Envia: Depositos do aluno
  - Recebe: Token do aluno
  - Status V1: Real
  - Responsabilidade: Listar apenas dados do proprio aluno.
- Area: Resgates do App
  - Endpoint/Entidade: `GET /v1/me/redemptions`
  - Envia: Resgates do aluno
  - Recebe: Token do aluno
  - Status V1: Real
  - Responsabilidade: Listar apenas dados do proprio aluno.
- Area: Catalogo de recompensas
  - Endpoint/Entidade: `GET /v1/rewards?school_id=...`
  - Envia: Recompensas
  - Recebe: `school_id`
  - Status V1: Real
  - Responsabilidade: Retornar recompensas da escola.
- Area: Criar resgate
  - Endpoint/Entidade: `POST /v1/redemptions`
  - Envia: Codigo, status e datas
  - Recebe: `reward_id`, token do aluno
  - Status V1: Real
  - Responsabilidade: Debitar saldo, controlar estoque, pendencias e expiracao.
- Area: Consultar codigo
  - Endpoint/Entidade: `GET /v1/redemptions/code/{code}`
  - Envia: Resgate
  - Recebe: Codigo
  - Status V1: Real
  - Responsabilidade: Validar existencia e expiracao.
- Area: Entregar resgate
  - Endpoint/Entidade: `POST /v1/redemptions/{redemption_id}/deliver`
  - Envia: Resgate entregue
  - Recebe: Token admin
  - Status V1: Real
  - Responsabilidade: Entrega por admin autorizado.

## Campos Oficiais

### Aluno

Aluno:
- Campo: `id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Identificador interno.
- Campo: `name`
  - Tipo: string
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Nome exibido.
- Campo: `school_id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Escola do aluno.
- Campo: `class_id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Turma do aluno.
- Campo: `class_name`
  - Tipo: string
  - Obrigatorio: no Totem/ranking
  - Fonte: Backend
  - Observacao: Nome da turma.
- Campo: `points_student_balance`
  - Tipo: integer
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Saldo individual em Bins.
- Campo: `status`
  - Tipo: enum
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: `ACTIVE` ou `INACTIVE`.

### Turma

Turma:
- Campo: `id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Identificador interno.
- Campo: `name`
  - Tipo: string
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Nome da turma.
- Campo: `segment`
  - Tipo: string
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Segmento escolar.
- Campo: `grade`
  - Tipo: string
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Serie/ano.
- Campo: `points_class_balance`
  - Tipo: integer
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Saldo coletivo em Bins.

### Deposito

Deposito:
- Campo: `event_id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Totem
  - Observacao: Deve ser unico para idempotencia.
- Campo: `class_id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Totem/Backend
  - Observacao: Turma pontuada.
- Campo: `student_id`
  - Tipo: UUID/null
  - Obrigatorio: Nao
  - Fonte: Totem/Backend
  - Observacao: Pode ser nulo se o descarte for sem login individual.
- Campo: `is_valid`
  - Tipo: boolean
  - Obrigatorio: Sim
  - Fonte: Totem/IA simulada
  - Observacao: Indica item aceito ou recusado.
- Campo: `detected_type`
  - Tipo: string/null
  - Obrigatorio: Nao
  - Fonte: Totem/IA simulada
  - Observacao: Categoria/tipo detectado.
- Campo: `size`
  - Tipo: enum
  - Obrigatorio: Sim
  - Fonte: Totem/IA simulada
  - Observacao: `SMALL`, `MEDIUM`, `LARGE`.
- Campo: `points_awarded_student`
  - Tipo: integer
  - Obrigatorio: Sim na resposta
  - Fonte: Backend
  - Observacao: Calculado pelo Backend.
- Campo: `points_awarded_class`
  - Tipo: integer
  - Obrigatorio: Sim na resposta
  - Fonte: Backend
  - Observacao: Calculado pelo Backend.
- Campo: `created_at`
  - Tipo: datetime
  - Obrigatorio: Sim na resposta
  - Fonte: Backend
  - Observacao: Data oficial do registro.

### Recompensa e Resgate

Recompensa_e_Resgate:
- Campo: `reward.id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Identificador da recompensa.
- Campo: `reward.name`
  - Tipo: string
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Nome exibido.
- Campo: `reward.description`
  - Tipo: string/null
  - Obrigatorio: Nao
  - Fonte: Backend
  - Observacao: Descricao curta.
- Campo: `reward.cost_points`
  - Tipo: integer
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Custo em Bins.
- Campo: `reward.category`
  - Tipo: string/null
  - Obrigatorio: Nao
  - Fonte: Backend
  - Observacao: Ex.: `CANTINA`, `ESCOLAR`.
- Campo: `reward.status`
  - Tipo: enum
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: `AVAILABLE`, `DISABLED`, `OUT_OF_STOCK`.
- Campo: `reward.stock_qty`
  - Tipo: integer/null
  - Obrigatorio: Nao
  - Fonte: Backend
  - Observacao: Estoque quando controlado.
- Campo: `redemption.id`
  - Tipo: UUID
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Identificador do resgate.
- Campo: `redemption.code`
  - Tipo: string
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Codigo de retirada/entrega.
- Campo: `redemption.status`
  - Tipo: enum
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: `PENDING`, `DELIVERED`, `CANCELED`, `EXPIRED`.
- Campo: `redemption.created_at`
  - Tipo: datetime
  - Obrigatorio: Sim
  - Fonte: Backend
  - Observacao: Criacao do resgate.
- Campo: `redemption.expires_at`
  - Tipo: datetime/null
  - Obrigatorio: Nao
  - Fonte: Backend
  - Observacao: Expiracao.
- Campo: `redemption.delivered_at`
  - Tipo: datetime/null
  - Obrigatorio: Nao
  - Fonte: Backend
  - Observacao: Entrega feita pelo admin.

## Regras para Mocks

Regras_para_Mocks:
- Regra: Centralizar mocks por frente em um unico arquivo ou service.
  - Obrigatorio: Sim
- Regra: Usar nomes de campos iguais aos contratos acima.
  - Obrigatorio: Sim
- Regra: Usar unidade `Bins` para pontos/saldo.
  - Obrigatorio: Sim
- Regra: Nao misturar nomes de recompensas, ranking ou saldos diferentes por tela.
  - Obrigatorio: Sim
- Regra: Marcar visualmente no codigo quando a origem for mockada ou simulada.
  - Obrigatorio: Sim
- Regra: Trocar mock por endpoint real sem alterar a interface visual do dado.
  - Obrigatorio: Sim
