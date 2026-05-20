# Totem Simulator

O Totem Simulator é uma interface web simples para simular o fluxo inicial de descarte do totem BinGo.

Esta versão usa a API real do backend BinGo para carregar alunos, turmas, rankings e registrar depósitos. Ela continua sem frameworks no frontend e não acessa banco de dados ou Supabase diretamente pelo navegador.

## Como abrir localmente

Antes de abrir o simulador, deixe o backend rodando em `http://localhost:8000` e aplique as migrations mais a seed:

```powershell
database/seeds/007_dev_deposit_flow_demo.sql
```

Depois sirva os arquivos estáticos:

```powershell
cd apps/totem_simulator
python -m http.server 8001
```

Abra no navegador:

```text
http://localhost:8001
```

Não existe etapa de build ou instalação de dependências para o frontend.

## Páginas disponíveis

- **Simulador de descarte**: permite escolher um aluno vindo da API, tamanho do item, validade e tipo detectado. O descarte é enviado para `POST /v1/deposits`.
- **Informações do aluno**: consulta `GET /v1/totem/students/{student_id}/summary` e mostra saldo, turma, estatísticas e histórico recente.
- **Rankings**: consulta `GET /v1/totem/rankings` e exibe alunos e turmas do maior para o menor saldo.

## Dados de desenvolvimento

O simulador espera a escola criada pela seed `007_dev_deposit_flow_demo.sql`:

- Escola Demo BinGo
- Turmas: 6º Ano A, 7º Ano B e 1ª Série A
- Alunos demo: Ana Silva, Lucas Costa, Pedro Santos, João Teste e Maria Oliveira
- Máquina demo: Totem Demo 01
- API key demo: `edge-demo-key`

No `app.js`, a configuração padrão é:

```js
const API_BASE_URL = "http://localhost:8000/v1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const MACHINE_API_KEY = "edge-demo-key";
```

A chave fica no frontend apenas porque este é um simulador de desenvolvimento. No totem real, ela deve ficar protegida no serviço local do Edge/Orange Pi.

## Próximo passo futuro

Evoluir o simulador para representar melhor o fluxo físico do totem, mantendo a integração com o backend real para registrar depósitos e atualizar saldos reais.
