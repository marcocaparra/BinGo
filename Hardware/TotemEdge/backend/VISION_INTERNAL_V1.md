# Visão interna no Totem Edge — 2026-10-27

Implementação interna para revisão. **Não habilita operação física.**
`OFFLINE` e `can_start_deposit=false` permanecem obrigatórios.

## Preflight e autoridade

Lidos nesta ordem: `Software/docs/STATUS_12-08.md`, `LOCAL_API_V1.md`,
`../frontend/INTEGRATION_V1.md`, `Software/apps/totem_ui/VISION_HANDOFF.md`,
`Software/docs/descarte/FLUXO_ECOSSISTEMA_DESCARTE_V1.md` e
`Software/docs/operacao-offline.md`. Inspecionados captura, serviço/provider da
UI, classificação/câmera e recuperação local/Simulator. Base: develop `9f385ab`,
com PRs #47 e #48 integrados.

O fluxo oficial distingue reconhecimento, recusa, inconclusão e falha técnica;
Gemini apoia somente incerteza do principal. A decisão posterior documentada
em INTEGRATION_V1 mantém Orange Pi direto: o texto antigo sobre Arduino e
serviço local ainda futuro não desfaz a fundação atual.

Há divergências no **código de referência**, sem dois contratos oficiais
concorrentes: `analyze_primary_with_fallback` usa Gemini em exceção da AWS;
o prompt Gemini mistura impossibilidade de confirmar com `rejected`;
o JS transforma HTTP 501 secundário em reconhecimento manual de `unknown`.
Esses caminhos não foram transferidos. A ligação ao ciclo, revisão,
categorias e auditoria permanece bloqueada até aprovação.

## Propostas pendentes de aprovação

Estas propostas foram apresentadas na conversa antes da implementação.
Não alteram o contrato HTTP nem o registro central.

**Resultado/candidatos:** preservar `VisionResult` com os cinco campos
`status/itemId/candidateIds/confidence/origin`. IDs visuais fechados:
`battery/cable/phone/small/unknown`, distintos de categorias oficiais.
Candidatos ordenados, sem duplicatas ou scores individuais inventados.
Reconhecimento exige classe conhecida entre candidatos; nos demais estados
`itemId=null`. `unknown` é uma pista, não evidência de domínio eletrônico.
Propor `needs-secondary` como inconclusão também após Gemini; não autoriza
terceira chamada. A confiança é a medida agregada legada, não probabilidade
calibrada da categoria ou comprovação de segurança. Falta definir limiar
secundário, aceitação física, modelo imutável e objetos de classes diferentes.

**Correspondência:** nenhum mapeamento foi implementado, inclusive os simples.

| ID visual | Proposta | Revisão necessária |
| --- | --- | --- |
| battery | BATTERY | Labels legadas incluem battery charger |
| phone | MOBILE_DEVICE | Labels legadas incluem telephone |
| cable | CABLE_WIRE | Gemini inclui carregador/adaptador |
| small | Sem correspondência automática | Mistura periféricos, placas, componentes e lâmpadas |
| unknown | Sem correspondência automática | Não comprova domínio eletrônico |

Para `small`, propor refinar taxonomia/labels antes de atribuir PERIPHERAL ou
OTHER_EWASTE. Não inferir categoria/validade por tamanho. UNKNOWN/UNIDENTIFIED
continua restrito à regra oficial: domínio eletrônico confirmado e revisão.

**Inconclusão/falha técnica:** reutilizar a distinção oficial. No transporte
privado Gemini, `inconclusive` representa dúvida/imagem vazia/impossibilidade de
confirmar e é projetado em `needs-secondary`. Risco/item grande também não
comprovam objeto não eletrônico: permanecem inconclusivos e bloqueados nesta
fatia. AWS ausente/erro/timeout falha fechado sem Gemini. Principal inconclusivo
sem Gemini mantém inconclusão. Erro Gemini é falha técnica, nunca recusa ou
reconhecimento manual. Nenhuma recusa/teste segue para register-deposit-v1.

**Revisão/auditoria:** propor confirmação ou seleção somente entre candidatos
oferecidos, após domínio eletrônico confirmado. Reutilizar futuramente origens
oficiais `AI_CONFIRMED/USER_CORRECTED/UNIDENTIFIED`, sem override de não eletrônico
por UNKNOWN. Auditoria proposta: mesmo `event_id`, resultado original
normalizado, ação/seleção humana, resultado canônico, provedor/modelo, versão
da política e instante. Sem imagem/base64/headers/credenciais/resposta bruta.
Ainda definir armazenamento, esquema, retenção, identidade/autorização do
revisor e atomicidade. Nada disso foi persistido ou exposto nesta entrega.
O payload central continua com sete campos.

## Arquitetura e reaproveitamento

`app.state.vision` recebe `InternalVision` no lifespan FastAPI, com o mesmo
cliente HTTPX assíncrono para Gemini. Sem servidor/container adicional, rota
nova ou import de UI no runtime. `CaptureService` conserva sua interface e
continua sem câmera/provedor conectado na composição de produção. A ligação
ao ciclo aguarda os contratos acima. O novo serviço não acessa SQLite.

`vision_policy.py` reutiliza constantes e `classify_labels` do PR #48, apenas
reformatados. Cópia localizada para preservar a origem e evitar dependência
de UI no container. Teste de equivalência AST da função e nove casos originais
preservam comportamento. Evoluções devem reconciliar os dois locais ou extrair
pacote compartilhado em tarefa autorizada. São heurísticas experimentais;
recusas usam confiança agregada legada, sem homologação para decisão física.

`vision.py` adapta detect_labels, prompt/schema e normalização Gemini:

- AWS em thread durante rede; credenciais explícitas backend, TLS do SDK,
  sem descoberta de perfil/IMDS ou endpoint implícito. Reutilizados 20 labels,
  mínimo 55 e threshold 0,75; tuning do gateway não foi copiado.
- AWS: connect 3s/read 5s, uma tentativa, total 10s. Cancelamento/timeout mantém
  o bloqueio enquanto a thread vive; não acumula chamadas por novas tentativas.
- Gemini: HTTPS fixo, segredo em header, sem redirects, até 10s/tentativa;
  no máximo uma nova tentativa após 1s para rede/timeout/429/503, total 21s.
- Uma classificação por instância, concorrência recusada sem fila de fotos.
- JPEG/PNG, bytes até 5 MiB, MIME coerente, integridade, um frame e limite
  técnico de 16 milhões de pixels. Pillow verifica/decodifica em memória,
  sem redimensionar/salvar imagem; rejeita bombas de descompressão.
- Gemini: até 64 KiB, JSON estruturado, uma candidata/parte, término STOP,
  decisão e confiança válidas. Labels/observações: tipos estritos, números
  finitos dentro da faixa, IDs/candidatos coerentes, sem coerção/clamping.
- `Frame/Observation.simulated=true` por padrão. Doubles também são simulados
  por padrão; a marca percorre a cascata e a guarda de captura existente a
  bloqueia antes de REVIEW. Não há flag para habilitar ONLINE/etapa física.

Limites novos de memória/tempo são salvaguardas técnicas locais, não SLO ou
critério de aceite físico. Faltam medições no Orange Pi Zero 3 de 2 GB.

## Configuração e preservação

Exemplos backend/deploy documentam AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
AWS_SESSION_TOKEN opcional, AWS_REGION, GEMINI_API_KEY, GEMINI_MODEL,
BINGO_GEMINI_TIMEOUT_SECONDS (0,1–10), BINGO_GEMINI_TRANSIENT_RETRIES (0 ou 1).
Configuração inválida desabilita o serviço privado, preservando liveness/status.
Ausência de credenciais não faz tráfego; startup não chama provedores.
O alias herdado `gemini-flash-lite-latest` não é versão imutável homologada.
Compose encaminha opções ao mesmo backend; não imprimir config com segredos,
usar `config --quiet`. O smoke remove também AWS_/GEMINI_ herdados.

Nenhuma rota/estado/schema local mudou. Controller, UI original, Simulator,
frontend Edge, migrations, Edge Functions e economia permanecem intactos.
Preservados UUID/event_id, slot único, CAS, payload imutável, idempotência e
recuperação. Fotografias e respostas brutas não são gravadas pelo serviço.
Os testes novos não registram depósitos nem pontos. A regressão existente de
recuperação usa exclusivamente ledger central controlado e SQLite temporário.

## Validação e próximos passos

| Verificação executada | Resultado |
| --- | --- |
| `uv run --locked pytest -q` (Python 3.12.14) | 248 aprovados, zero falhas/skips; 137 anteriores + 111 novos |
| `uv format --check -- app tests` | 27 arquivos aprovados |
| JS: provider UI e Simulator, camera_controller, backend_client e runtime | 65 aprovados, zero falhas/skips |
| Python: UI edge_vision_service_test | 15 aprovados |
| Python: Simulator vision/tests/*_test.py | 30 aprovados, transportes controlados/loopback |
| Deploy: unittest tests/test_runtime.py (host Python 3.14.2) | 6 aprovados, zero skips |
| `docker compose --env-file .env.example config --quiet` | Aprovado |
| `docker buildx build --check -f Dockerfile ..` | Aprovado, sem avisos após recuperação do Docker |
| Builds `linux/amd64` e `linux/arm64 --load` | Aprovados, Python 3.12.15 e 24 dependências de produção locked, sem compilação nativa |
| Backend dentro da imagem Linux AMD64, sem rede externa/rootfs readonly | 248 aprovados, zero falhas/skips |
| Deploy dentro da imagem Linux AMD64 | 6 aprovados, zero skips |
| Backend dentro da imagem Linux ARM64 em QEMU, sem rede externa/rootfs readonly | 248 aprovados, zero falhas/skips; 215,97s de pytest |
| Deploy dentro da imagem Linux ARM64 em QEMU | 6 aprovados, zero skips |
| `python -B validation/container_smoke.py --image bingo-totem-edge:internal-vision-test` | Aprovado: SQLite/recuperação, OFFLINE/false, segurança e 50 estáticos íntegros |
| Lock exportado + download somente wheels CPython 3.12/Linux ARM64 | 24 dependências de produção disponíveis, incluindo Pillow/pydantic-core aarch64 |
| `git diff --check` e diff das áreas proibidas | Aprovado; áreas proibidas sem alterações |

Na primeira execução da suíte nova, houve dois erros por nome parametrizado
longo demais para tmp_path no Windows e uma asserção sobre texto em vez de
código do CycleError. Corrigidos; a execução completa final passou.
Uma tentativa adicional de camera_flow de navegador não iniciou por ausência
de resolução local de Playwright; esse teste de UI não integra os 65 unitários
JS aprovados e não foi homologado nesta tarefa. A UI não foi alterada.

Na primeira tentativa, Docker Desktop encerrou com status 150 e o pipe
`dockerDesktopLinuxEngine` ficou ausente. A tentativa está preservada em
deploy/.validation/bingo-container-test-003679e31973/. Após o usuário abrir o
Docker novamente, o diagnóstico encontrou sockets temporários obsoletos
`dockerInference` e `userAnalyticsOtlpHttp.sock`; o reinício normal também travou.
Com a engine parada, foram encerrados somente os processos Docker Desktop
travados e preservada a pasta temporária como
`C:/Users/Predeus/AppData/Local/Docker/run.stale-20261027-191908`.
O Docker recriou `run` e voltou a responder. Nenhum volume, banco ou container
preexistente foi apagado, nem houve mudança de configuração do Docker/WSL.

Docker 29.0.1, Linux x86_64 e aproximadamente 9,669 GiB na VM de desenvolvimento.
O PostgreSQL local existente respondeu `accepting connections` ao pg_isready;
não foi resetado/migrado e não recebeu registros de visão. A validação de
persistência do Totem usa exclusivamente SQLite de teste em volumes isolados.

Smoke AMD64 aprovado: deploy/.validation/bingo-container-test-5304487de2b0/report.json.
Mesmo event_id, payload de sete campos, estado pending, journal e integridade
preservados após restart/force-recreate; sem linha duplicada ou reenvio central.
UID 10001, rootfs readonly, loopback, sem dispositivos/privilégios; um processo
Uvicorn. Memória de repouso: 45,94 MiB nas três amostras; pico cgroup observado:
64.794.624 bytes. Imagem: 91.359.224 bytes de conteúdo e 333 MB de disk usage no
engine containerd. Healthy em 21,04s pelo Compose. Essas medições de desktop
não comprovam consumo/latência no Orange Pi de 2 GB ou pico de análise real.

Testes dentro da imagem usam as dependências dev exportadas do lock em wheels
montados readonly e extraídos só em tmpfs; produção continua sem pytest. Testes
de backend, fonte de referência para comparação AST e testes de deploy são
montados readonly; `--network none` impede acesso externo. Banco temporário e
conexão HTTP de loopback controlada permanecem disponíveis aos testes.

ARM64 emulado: a primeira execução concorrente com pytest passou pelo startup
do Uvicorn, mas encontrou health ainda `starting` após 319,79s
(deploy/.validation/bingo-container-test-6e400ff38d9e/report.json). A segunda,
isolada, passou pelo início e pelo restart, mas falhou no force-recreate após
5 minutos: os logs do healthcheck mostraram probes excedendo 30s
(deploy/.validation/bingo-container-test-c6f935aca72d/report.json).
Uma medição manual concorrente foi interrompida pelo teardown do smoke com
exit 137 após 39,11s; não é um benchmark de probe concluído.
Somente o modo de teste `--emulated` foi ajustado para timeout de probe 90s e
espera máxima 600s. Mantidos start-period emulado 180s, verificação real de
health/status e todos os asserts de persistência. Não altera o healthcheck da
imagem/Compose de produção (3s), os limites AWS/Gemini ou qualquer gate físico.
Essa tolerância de QEMU não homologa o tempo de inicialização no Orange Pi.

Os testes novos cobrem reconhecimento, recusa, fallback seletivo, inconclusão,
MIME/conteúdo/tamanho/pixels, malformações, timeout/deadline, indisponibilidade,
tentativas limitadas, concorrência/cancelamento, proveniência simulada,
ausência de foto no SQLite e preservação de OFFLINE/false. A regressão completa
mantém recuperação e idempotência. Todas as imagens são locais/em memória e as
respostas controladas. Sem inferência ao vivo, câmera/GPIO, Supabase hospedado,
commit, push, merge, deploy ou criação de PR.

## Arquivos desta entrega

Criados: `app/services/vision.py`, `app/services/vision_policy.py`,
`tests/test_vision.py` e `VISION_INTERNAL_V1.md`.

Alterados no backend: `app/main.py`, `tests/conftest.py`, `pyproject.toml`,
`uv.lock`, `.env.example`, `README.md` e `LOCAL_API_V1.md`.
Alterados no deploy: `.env.example`, `compose.yaml` e
`validation/container_smoke.py` (remoção de credenciais herdadas e tolerância
de tempo somente em QEMU) e
`README.md` (24 dependências e referência às evidências atuais).

Parecer: pronto para revisão como PR de preparação interna, com validação Docker
pendente antes de merge. Não está pronto para integração operacional ou física.

Para completar: aprovar resultado/categorias/revisão/auditoria; escolher e
homologar câmera/driver/ciclo de vida; integrar confirmações confiáveis de
fechamento e ciclo mecânico em trabalho próprio; definir recuperação de
movimento indeterminado e prontidão completa; medir memória/latência e segurança
no equipamento. Só então ligar a visão à sessão e avaliar liberação operacional.
