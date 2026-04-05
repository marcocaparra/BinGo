# BinGo V1 — Modelo de Dados (Rascunho Inicial)

## 1. Objetivo

Este documento define a modelagem inicial do banco de dados do BinGo V1.

O objetivo é transformar as regras do produto em entidades, relacionamentos e restrições de dados, servindo como base para a criação do schema SQL, migrations e backend.

Este documento ainda é um rascunho técnico e pode evoluir conforme as decisões do projeto forem refinadas.

---

## 2. Escopo do V1

O modelo de dados inicial deve atender estas áreas do sistema:

- cadastro de escolas, turmas e alunos
- autenticação básica do aluno por PIN
- registro de descartes
- sistema de pontuação individual e por turma
- catálogo de recompensas
- resgates com código único
- validação de entrega por admin
- auditoria básica de ações importantes
- suporte futuro para multi-escola

Fora de escopo neste momento:

- armazenamento de imagens
- missões avançadas
- marketplace
- múltiplos tipos complexos de recompensa
- relatórios analíticos avançados

---

## 3. Entidades principais

### 3.1 School

Representa uma escola cadastrada no sistema.

Campos iniciais:
- id
- name
- created_at
- updated_at

Observações:
- mesmo que o piloto use uma única escola, a modelagem já deve suportar multi-escola

---

### 3.2 Class

Representa uma turma da escola.

Campos iniciais:
- id
- school_id
- segment
- grade
- name
- points_class_balance
- created_at
- updated_at

Observações:
- uma turma pertence a uma escola
- a turma possui saldo próprio para ranking/premiação coletiva

---

### 3.3 Student

Representa um aluno da turma.

Campos iniciais:
- id
- school_id
- class_id
- name
- pin_hash
- is_activated
- points_student_balance
- status
- created_at
- updated_at

Observações:
- aluno pertence a uma escola e a uma turma
- PIN não deve ser salvo em texto puro
- `is_activated` indica se o aluno já criou o PIN no primeiro uso
- `status` pode ser usado para ativo/inativo sem apagar histórico

---

### 3.4 Admin

Representa usuários administrativos do sistema.

Campos iniciais:
- id
- school_id
- name
- email
- role
- created_at
- updated_at

Observações:
- papéis iniciais previstos: ADMIN_CONQUISTA e ADMIN
- admins validam e entregam recompensas

---

### 3.5 Machine

Representa um totem/máquina do BinGo instalado em uma escola.

Campos iniciais:
- id
- school_id
- name
- status
- firmware_version
- last_seen
- bin_full
- camera_ok
- net_ok
- created_at
- updated_at

Observações:
- a máquina pertence a uma escola
- deve permitir telemetria e status operacional

---

### 3.6 Reward

Representa uma recompensa disponível para resgate.

Campos iniciais:
- id
- school_id
- name
- description
- cost_points
- category
- is_active
- created_at
- updated_at

Observações:
- a recompensa pertence a uma escola
- `stock_qty` pode ser opcional no V1
- `is_active` controla disponibilidade

---

### 3.7 Deposit

Representa um descarte realizado no sistema.

Campos iniciais:
- id
- event_id
- school_id
- machine_id
- class_id
- student_id
- is_valid
- detected_type
- size
- points_awarded_student
- points_awarded_class
- created_at

Observações:
- `student_id` pode ser nulo quando o descarte ocorre sem login
- `class_id` continua obrigatório porque a turma recebe pontos mesmo sem login individual
- `event_id` deve ser único para evitar duplicação em sincronização
- `detected_type` pode guardar algo como "mouse", "pilha", "teclado"
- `size` deve guardar SMALL, MEDIUM ou LARGE

---

### 3.8 Redemption

Representa um resgate de recompensa realizado por um aluno.

Campos iniciais:
- id
- school_id
- student_id
- reward_id
- code
- status
- request_channel
- created_at
- expires_at
- delivered_at
- delivered_by_admin_id

Observações:
- `code` deve ser único
- `status` inicial esperado: PENDING
- `request_channel` no V1 será TOTEM
- entrega só pode ser feita por admin

---

### 3.9 AuditLog

Representa registro de auditoria de ações importantes do sistema.

Campos iniciais:
- id
- school_id
- actor_type
- actor_id
- action
- metadata
- created_at

Observações:
- usado para rastrear ações sensíveis
- exemplos: entrega de resgate, cancelamento, reset de PIN, alteração de recompensa

---

## 4. Relacionamentos principais

- uma school possui classes
- uma school possui students
- uma school possui admins
- uma school possui machines
- uma school possui rewards
- uma school possui deposits
- uma school possui redemptions

- uma class pertence a uma school
- uma class possui students
- uma class possui deposits

- um student pertence a uma school
- um student pertence a uma class
- um student possui deposits
- um student possui redemptions

- uma machine pertence a uma school
- uma machine possui muitos deposits

- uma reward pertence a uma school
- uma reward possui redemptions

- uma redemption pertence a um student
- uma redemption pertence a uma reward
- uma redemption pode ser entregue por um admin

---

## 5. Regras de integridade iniciais

- `students.pin_hash` nunca armazena o PIN em texto puro
- `redemptions.code` deve ser único
- `deposits.event_id` deve ser único
- `students.points_student_balance` não pode ser negativo
- `classes.points_class_balance` não pode ser negativo
- `deposits.student_id` pode ser nulo
- `redemptions.status` deve aceitar apenas valores controlados
- `admins.role` deve aceitar apenas valores controlados
- `machines.status` deve aceitar apenas valores controlados
- logs e histórico de descarte não devem ser apagados sem regra explícita

---

## 6. Decisões já consideradas no modelo

- login do totem pode ser opcional no descarte
- sem login individual, ainda existe pontuação para turma
- resgate no V1 é feito apenas no totem
- mobile no V1 é consulta, não resgata
- entrega da recompensa acontece no admin
- o modelo já considera expansão para multi-escola

---

## 7. Pontos ainda em aberto

- definir lista final de enums:
  - machine status
  - redemption status
  - admin role
  - student status
  - deposit size

- decidir política exata de expiração de código

---