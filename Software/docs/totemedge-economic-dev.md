# Homologação econômica DEV com mecânica simulada — 02/11/2026

## Atualização autorizada do principal — 02/11

O responsável autorizou a atualização local. Build e recriação controlada apenas
de `dev-central` e `totem-edge-dev` no projeto existente `bingo-totem-edge` concluídos;
ambos saudáveis. Proxy, câmera, outros projetos e volume `bingo-totem-edge_vision-dev-data`
preservados. Política exclusiva `C:/BinGoDevSecrets/dev-policy-economic-main.json`
com opt-in true, projeto bingo-dev; a política compartilhada anterior não foi alterada.
Para futuros comandos Compose do principal, BINGO_DEV_POLICY_FILE deve apontar
para esse novo arquivo. Os demais caminhos privados continuam iguais.

Postflight: health `SUPABASE_DEV_ECONOMIC`, economic_registration=true,
mechanical_source=SIMULATED. Webcam Integrated Camera presente e livre; captura
e inferência reais serão exercitadas pelo aluno durante o teste. UI principal
aberta sem erros de JavaScript, zero recompensas antecipadas. Comparação por
hash comprovou preservação de cycles/transitions/journal/identidades/visão
existentes (cinco sessões), e os saldos DEV permaneceram iguais ao preflight.
Outbox nova inicialmente vazia. Backup SQLite e baseline dos saldos em
`C:/BinGoDevSecrets/homologation-economic-20261102`, fora do repositório.

Acesso: http://127.0.0.1:8000/ (sem runtime=demo); atualizar com Ctrl+F5. Aluno
seleciona turma/nome e usa PIN DEV; preservados os PINs de abertura/hatch.
Colocar um eletrônico, declarar retirada da mão, aguardar foto/análise reais,
confirmar/corrigir, concluir hatch/retorno simulados e aguardar recibo central.
Avisar ao aparecer a recompensa, preferencialmente antes de Concluir, para
correlacionar event_id, depósito, saldos, recibo e replay idêntico.

Ainda não foi executado descarte pelo aluno nesta rodada. Crédito real,
visualização final e replay hospedado aguardam esse teste. Nenhuma produção,
Function/migration remota, commit ou push foi alterado. As notas abaixo sobre
containers não atualizados descrevem a entrega anterior à autorização.

Decisão do responsável: mecânica simulada pode conceder pontuação **real no
Supabase DEV**. Isto é homologação econômica, distinta do protótipo demo sem
créditos. Esta decisão substitui a restrição anterior descrita no relatório de
integração e nas notas históricas de MAIN_DEV/LOCAL_API/INTEGRATION.

## Implementação

Autorização explícita `economic_registration: true` no arquivo privado de
DevPolicy, false por padrão. O modelo exige booleano real e project_ref literal
`ddxmohrjcxuibswmrtla`. O transporte só alcança esse projeto e permite o POST
register-deposit-v1 apenas com opt-in. O broker continua sendo o único portador
da chave técnica. Não há alteração em RPC, Edge Function, cálculo, PIN ou câmera/IA.

Somente VisionDevSettings com identidade DEV e opt-in instala DevEconomy. A
conclusão SIMULATED/SUCCEEDED de CONFIRM_INITIAL_STATE grava atomicamente uma
outbox local, sem transformar o evento em prova física. Exige os quatro tipos
de comando concluídos, identidade correspondente ao projeto/máquina/escola,
visão concluída, câmera DEVICE, inferência PROVIDER e decisão canônica persistida.
Reutiliza category/source da decisão existente; não mapeia classes específicas.
UNKNOWN/UNIDENTIFIED só pode vir da decisão autorizada, não de falha técnica.

`dev_economic_outbox` conserva payload imutável, event_id, escopo, erro e recibo.
As linhas cycles continuam simulated=1, physical_confirmed=0, payload/receipt
físicos nulos. Journal de mecânica, provenance e transitions com
DEV_SIMULATED_ECONOMIC_QUEUED/CONFIRMED conservam a origem. No Supabase, a
auditoria existente registra máquina e event_id; a origem simulada é correlacionada
ao journal local pelo mesmo event_id. Não foi acrescentado campo ao contrato
econômico remoto. O armazenamento local não deve ser removido na homologação.

Worker faz retry com os mesmos dados; perda de resposta/reinício não recriam
evento. Revalida elegibilidade antes de enviar. Slot fica reservado até recibo
e encerramento explícito. GETs não registram descartes nem disparam mecânica.
O frontend consulta a outbox: Pending não mostra valores; CONFIRMED reutiliza a
tela final existente e os totais do recibo. Concluir libera o slot pela API DEV.

O perfil operacional físico permanece com a restrição anterior. O modo demo e
os perfis sintéticos continuam sem créditos. Esse opt-in não é aceito como
configuração de produção; o transporte e o modelo DEV não aceitam outro projeto.

## Validação e limites

Rodada executada: 752 testes backend aprovados (zero falhas/skips), incluindo
os dois novos de economia DEV; 147 focados aprovados; 27 contratos JavaScript
aprovados. Ruff dos módulos econômicos/DEV alterados e sintaxe JavaScript passaram.

Novos testes controlados cobrem recusa de sessão não concluída, opt-in desligado,
projeto diferente, fila sem recibo, perda de resposta após commit simulado pelo
double central, reabertura SQLite, retry sem duplicação e preservação de origem.
Esses testes usam journal/visão/HTTP controlados: **não comprovam crédito real
hospedado nem uma nova captura/IA real**. As provas SQL/HTTP locais da rodada
anterior continuam separadas e não contam como homologação hospedada deste fluxo.

O critério de aprovação solicitado permanece pendente: containers do principal
carregam a versão anterior em suas imagens, sem bind mount do código. Não foram
substituídos, reiniciados, copiados ou reconfigurados, respeitando a instrução de
não fazer deploy. A política privada também não foi modificada. Não houve novo
container, commit, push, migration remota ou crédito hospedado nesta rodada.

## Próxima execução autorizada

Aplicar o código nos dois serviços existentes totem-edge-dev e dev-central,
habilitando economic_registration na política privada do bingo-dev, sem criar
containers adicionais nem alterar volumes. Fazer isso somente quando a restrição
de atualização do runtime for revista pelo responsável. Em seguida, o aluno usa
seu PIN DEV na interface; completar foto/IA reais, confirmar/corrigir, hatch e
retorno simulados. Conferir recibo, saldo anterior/posterior, XP, depósito e
auditoria remotos pelo event_id. Repetir o mesmo envio após perda de resposta e
confirmar um único crédito. Testes de câmera/IA/mecânica falha e ciclo interrompido
devem produzir zero registro econômico. Não usar sessões antigas como novos
descartes nem conceder créditos retroativamente para contornar essa prova.
