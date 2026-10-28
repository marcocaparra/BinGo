# Backend local do Totem Edge V1

FastAPI orquestra sessões e persistência local. Supabase/PostgreSQL/Edge Functions
mantêm autenticação central, registro definitivo, idempotência e economia.

**O Totem não está operacional.** /local/status permanece OFFLINE/false, mesmo
com health central saudável. O controller operacional padrão é indisponível.
Há um simulador mecânico privado para desenvolvimento/testes, sem GPIO,
câmera física ou ligação à autorização de descarte. Contrato, uso e limites em
[Controller mecânico — Incrementos 1 e 2](MECHANICAL_INTERNAL_V1.md).

O [ambiente Docker isolado de simulação — 3A](../deploy/SIMULATION.md) executa
esse backend com central bloqueada, SQLite próprio e harness interno, sem
integração de movimentos ao frontend. O runtime operacional padrão é preservado.

Os [contratos locais](LOCAL_API_V1.md) foram documentados antes das novas rotas.
O [relatório completo](../frontend/INTEGRATION_V1.md) descreve estados, mudanças
frontend, recuperação, evidências e contratos físicos/visão pendentes.

## Executar com uv

Na pasta Hardware/TotemEdge/backend/:

~~~powershell
uv sync --locked
uv run --locked uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
~~~

Abrir http://127.0.0.1:8000/. UI/API compartilham origem. Demonstração explícita
em /?runtime=demo, com aviso global e sem chamadas de negócio. O modo padrão
consulta a API local e bloqueia o fluxo até prontidão completa.

Não abrir CORS amplo nem configurar base URL remota no frontend. Manter bind
loopback. Novas rotas verificam Host/origem e exigem JSON + X-Totem-Request: 1
nas escritas. O comando desativa access logs para evitar queries arbitrárias.

Produção sem testes pode usar uv sync --locked --no-dev e uv run --locked
--no-dev uvicorn ... . Usar somente um worker/instância por arquivo SQLite:
a trava do arquivo recusa outra instância para não reconciliar operação ativa
de outro processo.

## Configuração por ambiente

| Variável | Finalidade |
| --- | --- |
| BINGO_SUPABASE_URL | URL raiz do projeto, sem /functions/v1, usuário/senha, query ou fragmento. HTTPS remoto; HTTP só loopback. |
| BINGO_MACHINE_ID | UUID hifenizado da máquina provisionada nesse ambiente. |
| BINGO_MACHINE_API_KEY | Chave da máquina exclusivamente server-side; nunca anon/service role/Secret API Key. |
| BINGO_BACKEND_TIMEOUT_SECONDS | Limite técnico finito positivo por consulta (fases HTTP e total), default 5s; não define polling/SLO. |
| BINGO_SQLITE_PATH | Arquivo local persistente; default absoluto backend/.data/totem.sqlite3. Pode futuramente apontar a volume. |

~~~powershell
Copy-Item .env.example .env
# Preencha somente no backend pelo canal autorizado.
uv run --locked --env-file .env uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
~~~

uv pode carregar .env; o serviço não lê esse arquivo automaticamente.
Configuração central é carregada no startup; reinicie após alterações.
API key não recebe strip/mudança de caixa/normalização Unicode; o transporte
exige headers ASCII sem controles. Configuração inválida/ausente não faz tráfego.

TLS verificado, redirects/proxies implícitos desabilitados, sem retry automático.
Não são logados PIN, headers técnicos, corpos ou exceções remotas brutas.
Nenhum secret vai ao JS/SQLite; não há JWT/token de autenticação local inventado.
Não existe env para habilitar hardware, ONLINE ou selecionar o simulador no
runtime operacional. O perfil 3A exige outra entrada/fábrica e configuração de
desenvolvimento explícita; variáveis desse perfil são recusadas na entrada operacional.

## Contratos preservados e novos

GET /health mantém HTTP 200 {"status":"ok"}, somente liveness, sem consulta remota.

GET /local/status mantém HTTP 200, Cache-Control: no-store e:

~~~json
{
  "status": "OFFLINE",
  "can_start_deposit": false,
  "message": "Totem temporariamente indisponível. Estamos sem conexão no momento."
}
~~~

Cada consulta verifica health central se configurado. O sinal central não
comprova câmera, visão ou equipamento. A mensagem preserva o contrato anterior,
não diagnostica precisamente internet/IA. Sem cache, polling ou chamada central
durante startup ou /health.

As operações novas /local/context e /local/sessions… estão em LOCAL_API_V1.md.
Contexto, identificação e início exigem disponibilidade completa: permanecem
bloqueados no runtime atual. Consulta de sessão e recuperação funcionam offline;
retry só aceita confirmação física/payload/escopo central já persistidos.
Nenhuma rota recebe confirmação física ou payload de descarte do browser.

Clientes implementados: health-v1, totem-context-v1, totem-student-pin-v1 e
register-deposit-v1, nas rotas nativas /functions/v1/<nome>. Headers técnicos
exclusivamente server-side; respostas tipadas e projetadas. PIN confirmado deve
corresponder aos IDs solicitados. Erro de PIN é distinto de falha técnica.

Registro aceita somente 201/200 e recibo consistente com evento/categoria/origem,
tipos e timestamp. Recompensas vêm dos snapshots; não há cálculo ou crédito local.
Falhas preservam pending e código seguro; não geram UUID substituto.

Resumo/rankings centrais foram inspecionados, mas não ganharam clientes/telas
sem necessidade na UI atual. Não copiar gateway/arquitetura/storage do Simulator.
POST /v1/deposits continua conceitual, não é alias local implementado.

## Organização

~~~text
app/main.py                 composição, lifespan, origem e arquivos estáticos
app/config.py               configuração server-side
app/central_contracts.py    payload de sete campos e projeções centrais
app/cycles.py               estados e snapshot público
app/mechanical.py           contrato privado de comandos/respostas mecânicas
app/mechanical_journal.py   identidade, histórico, CAS e recuperação mecânicos
app/storage.py              SQLite e recuperação transacional
app/routes/health.py        liveness
app/routes/local.py         readiness operacional seguro
app/routes/sessions.py      sessão/identificação/recuperação HTTP
app/services/status.py      saúde central separada da operação local
app/services/sessions.py    transições lógicas e reenvio do evento preservado
app/services/capture.py     guardas de câmera/visão; ligação operacional bloqueada
app/services/controller.py  controller indisponível e simulador temporizado isolado
app/services/mechanical.py  coordenação privada com persistência antes de despacho
app/services/vision.py      adaptadores privados AWS/Gemini no mesmo processo
app/services/vision_policy.py heurísticas de labels reutilizadas do PR #48
app/clients/supabase.py      Functions existentes autenticadas
~~~

O frontend é servido apenas por arquivos selecionados e assets. README, SQLite,
configuração e escolha arbitrária de arquivo por query não são expostos.

## SQLite e estados

Schema local versão 2: preserva cycles/transitions e migra versão 1 de forma
aditiva/transacional, acrescentando mechanical_commands/mechanical_history.
Mantém UUID por ciclo, command_id de início,
slot ativo único, transações BEGIN IMMEDIATE, WAL/synchronous FULL, CAS e trava
de instância. Não modifica schema central. BINGO_SQLITE_PATH do exemplo é
relativo ao cwd do backend; default sem env é absoluto. Banco inválido/versão
desconhecida/trava em uso não é apagado ou recriado silenciosamente.

`app.state.mechanical` coordena journal/controller sem ligação ao frontend.
Intenção e claim são persistidos antes de despacho; aceitação e conclusão são
distintas. Restart após possível despacho torna o ciclo indeterminado e mantém
o slot. Não há redisparo automático. Conclusão simulada durável conserva
`PHYSICAL_BLOCKED` e nunca define confirmação física ou elegibilidade econômica.
Detalhes de migração, estados e limitações em MECHANICAL_INTERNAL_V1.md.

IDENTIFYING → AUTHENTICATING → SAFETY é o fluxo lógico. Risco cancela antes de
etapa física; declaração segura fica PHYSICAL_BLOCKED. Retirei a mão só declara
retirada em DOOR_OPEN e responde 503 enquanto falta integração, sem solicitar
fechamento ou fabricar confirmação.

Estados físicos são reservas, não produzidos pelo runtime atual. Reinício em
etapa física sem evidência confiável vira INDETERMINATE e mantém bloqueio.
Preparação pré-física é cancelada no restart preservando o mesmo UUID.

Payload completo pode ser congelado em REVIEW antes de futura etapa irreversível.
Confirmação física tem campo reservado, sem setter/rota que a fabrique.
REGISTERING interrompido com evidência persistida volta a REGISTRATION_PENDING.
Retry manual usa os mesmos sete campos/UUID, não outra etapa física.

REGISTERED exige recibo central validado/persistido; sobrevive ao restart e
novo retry retorna recibo sem nova chamada. Finish → COMPLETED libera o slot
e conserva recibo/journal. Nenhum PIN, credencial, hash de PIN ou imagem é gravado.
Fingerprint não secreto do destino/máquina bloqueia reenvio a outro escopo
e não usa API key, permitindo rotação. Saída de visão tipada pode ser preservada
sem imagem; auditoria da correção depende do contrato/mapeamento pendente.

Não há sync periódico, fila de descartes offline ou reconciliação manual pública.
CANCELLED, TECHNICAL_FAILURE, INDETERMINATE, RETURN_REQUIRED e confirmação central
são distintos. Não apagar um descarte irreversível ou trocar event_id após erro.

Camera/vision têm Protocols internos activate/capture/deactivate e classify,
Frame/Observation marcados simulated=true por default. Captura exige DOOR_CLOSED
e estabilização de 1,5s; ausência/falha/simulação/inconclusivo bloqueiam.
Objeto recusado requer devolução, sem registro válido. Sem driver, dispositivo,
provedor conectado à captura ou rota de captura. Os adaptadores concretos privados
estão descritos em [VISION_INTERNAL_V1.md](VISION_INTERNAL_V1.md).
Nenhuma interface/implementação/simulação de controller foi criada.

## Testes e limites

~~~powershell
uv run --locked pytest -q
uv format --check -- app tests
~~~

Resultado final desta entrega: **137 testes em Python 3.12**, preservando os 84
anteriores, e a mesma suíte em Python 3.14. Configuração herdada é removida;
SQLite temporário e Supabase mockado/loopback, sem gravação hospedada.

Os testes exercitam identidade correta/incorreta, indisponibilidade, duplicação
lógica, sequência/concorrência, declaração de mão sem movimento, guardas de
captura/visão, recusa, recuperação crítica, UUID/payload imutáveis, resposta
perdida/replay sem pontos duplicados no stub, recibo confirmado após restart,
bloqueio com pending e erros sem secrets. Fixtures SQLite são dados de software,
não controller simulado. Movimentos físicos não foram implementados/testados.

O requisito permanece Python >=3.12, .python-version 3.12; não foram alterados
pyproject/uv.lock na fundação de sessão. A atualização de visão interna acrescenta
boto3 e Pillow ao lock. SQLite é biblioteca padrão. A fundação
anterior verificou wheels do lock para aarch64-manylinux_2_28 em 3.12/3.14, sem
executar ARM. [Ubuntu disponibiliza Python 3.12 arm64](https://packages.ubuntu.com/noble/python3.12)
e [uv suporta aarch64 Linux](https://docs.astral.sh/uv/reference/policies/platforms/);
isso não escolhe OS/modelo nem homologa Orange Pi. Faltam testes no equipamento,
inclusive trava fcntl, SQLite em volume e desempenho físico.

Testes JS/browser/integridade e limitações estão em INTEGRATION_V1.md.
Fontes relidas: STATUS atual, fluxo V1, offline, contratos Totem/App/backend,
integração Supabase V1, Totem Edge README e diagnóstico. As divergências de
Arduino/serviço local/câmera visual são registradas no relatório.

Próxima etapa após revisão: aprovar contratos pendentes de visão/auditoria/
reconciliação e integrar evidências confiáveis com a equipe física, câmera/visão
homologadas e prontidão completa. Não avançar para GPIO ou câmera real.

## Atualização de visão interna — 2026-10-27

O lifespan compõe `app.state.vision`, sem ligar o serviço à captura/sessão ou
readiness e sem nova rota. AWS é principal e Gemini atende apenas inconclusão;
falha técnica da AWS não aciona fallback. A configuração opcional está em
`.env.example`; credenciais somente no backend. O Compose mantém um serviço.
Consultar [propostas, arquitetura e evidências](VISION_INTERNAL_V1.md) antes de
qualquer ligação ao fluxo físico. A validação histórica acima não comprova as
dependências de visão novas nem operação em ARM.
