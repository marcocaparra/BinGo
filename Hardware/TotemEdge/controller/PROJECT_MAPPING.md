# Mapeamento físico pela frente e ciclo C/Python — 10/11/2026

Esta atualização usa o driver físico, JSON operacional, IPC V1 e journals já
implementados. Não há novo transporte, API HTTP, simulador ou executor alternativo.
A atuação permanece bloqueada, inclusive quando todos os campos forem declarados.

## Convenção e fonte de configuração

A convenção definitiva de orientação é **olhando o Totem pela frente**. O
responsável informou que os dois canais foram testados fisicamente no Orange Pi
Zero 3 e movimentaram os motores correspondentes. Esse relato de 10/11/2026 é a
evidência registrada em `mapping_reference`; não é uma execução física feita
pelos testes automatizados desta alteração. Não alterar o cabeamento.

O mapa confirmado está em [operational.example.json](operational.example.json).
Esse arquivo é o modelo de configuração, não um arquivo instalado na placa.
O arquivo local indicado por `BINGO_C_CONTROLLER_CONFIG` é a fonte efetivamente
carregada. Não foram modificados arquivos operacionais fora do repositório.

| Lado visto pela frente | Chip Linux | Canal Linux confirmado | Fechada | Aberta | RX/TX |
| --- | --- | --- | --- | --- | --- |
| Direita | pwmchip0 | 3 | 70° | 175° | Não confirmado |
| Esquerda | pwmchip0 | 4 | 113° | 5° | Não confirmado |

`pwm_channel`, `closed_degrees`, `open_degrees` e `intended_signal` são campos
explícitos por lado. O driver usa somente chip/canal e pulsos declarados; não
deriva canais de RX/TX ou de nomes PWM. Graus são metadados, sem conversão em ns.
Chip/canal e ângulos agora refletem o teste relatado. `intended_signal` permanece
`null` nos dois lados; não se atribui RX/TX por posição, nome ou convenção
anterior. Não há segunda tabela ativa de mapeamento em C ou Python.

O modelo agora declara `pwm_chip=0` nos dois lados. `period_ns`, `polarity`,
pad/conector, quatro pulsos e referências de calibração/conclusão/segurança
continuam `null`. O período 20.000.000 ns permanece referência histórica de
`dafc9ab`, sem virar calibração atual. Não foram inventados pulsos para os ângulos.

O preflight sem JSON agora informa `pwm_label=null`: ele não conhece o mapa
operacional. O diagnóstico configurado informa os números realmente lidos do
JSON. O laboratório antigo doorless-v1 conserva RIGHT/PWM3 e LEFT/PWM4 para
não reinterpretar seus IDs/resultados; esses rótulos não participam do driver
físico. A configuração física vigente é direita/3 e esquerda/4, ambas no chip 0.
O relato real substitui a convenção provisória inversa de 09/11. O objeto
`legacy_evidence` do preflight continua descrevendo `dafc9ab` (esquerda/3,
direita/4); não foi reescrito para aparentar que aquele commit já continha a
orientação física confirmada agora.

## Integração com o backend

`CProcessController` reaproveita seu leitor JSON com limite de 8 KiB e prazo de
I/O configurado para consultar tanto `--physical-preflight` quanto
`--physical-config ARQUIVO`. Antes de abrir o canal operacional, compara entre
C e Python o mapa, pulsos, ângulos, ligação pretendida, período, polaridade,
classificação da configuração e plano de ciclo.

Falha na validação/diagnóstico ou divergência entre interpretações deixa o
controller indisponível, sem criar journal C. Não há fallback para simulação.
O filho C recebe explicitamente `--config ARQUIVO`, inclusive em chamadas
programáticas de `open_operational`, sem depender da configuração herdada no
ambiente. Nenhum arquivo é reescrito para preencher defaults ou calibrar.

`ControllerReadiness` expõe `configured_physical` e `cycle_plan` no diagnóstico
privado existente. `execution_ready=false` e `source=UNAVAILABLE` são preservados.
Sem plano explícito acrescenta `CYCLE_POLICY_UNVERIFIED`; os bloqueios de mapa,
calibração, segurança, conclusão e despacho físico permanecem.

Diagnóstico existente, da pasta backend:

```sh
python -m app.controller_cli --config /caminho/absoluto/controller.json --backend-journal /caminho/absoluto/totem.sqlite3
```

O CLI retorna 2 por atuação bloqueada. No C, `--physical-config ARQUIVO` é somente
leitura e retorna 0 quando consegue emitir o relatório, sempre com prontidão falsa.

## Preparação do ciclo

O bloco opcional `physical.cycle` contém:

- `open_order`: `left_then_right` ou `right_then_left`;
- `close_order`: as mesmas opções, independentemente da abertura;
- `drop_reference`: referência ao critério de queda que ainda precisa de homologação;
- `homologation_reference`: registro da política de ciclo aprovada.

Todos começam `null` no modelo: a convenção dos canais não define ordem ou
tempo de abertura/fechamento. Não foi assumido movimento simultâneo ou espera
de seis segundos. Plano ausente/incompleto não recebe uma sequência implícita.

Quando explicitamente declarado, `pwm_build_cycle` em C e o modelo Python
produzem o mesmo plano de sete passos:

1. Abrir o primeiro lado configurado.
2. Abrir o outro lado.
3. Aguardar evidência de abertura.
4. Aguardar evidência de queda.
5. Fechar o primeiro lado configurado.
6. Fechar o outro lado.
7. Aguardar evidência de retorno inicial.

O plano é preparação de comandos, **não um motor de simulação nem autorização
para executar**. Ele não escreve PWM, cria intenções ou avança estados por tempo.
Não foi criado um provedor fictício de evidência. O executor que correlacionará
essas etapas com evidências reais e o mesmo ID/configuração ainda depende dos
critérios de conclusão/parada homologados. As primitivas atuais continuam
retendo UNKNOWN quando um movimento não é comprovado; o receptor de produção
recusa CYCLE_LOWER_HATCH e CONFIRM_INITIAL_STATE sem fabricar confirmação.

## Journal e recuperação

Não houve alteração dos schemas/journals nesta atualização. O C físico mantém
schema v3, origem e snapshot JSON imutáveis; o Python mantém seu journal durável
e a recusa de origem PHYSICAL. Alterar canais, ligação pretendida, calibração ou
plano muda o snapshot: o mesmo ID não é reinterpretado com os novos bytes.
Replays no journal Python conservam o resultado retido; consultas diretas ao C
com o mesmo ID e outra configuração recebem ID_CONFLICT.

Timeout, perda de resposta, falha parcial e reinício continuam conservando
UNKNOWN/INDETERMINATE e bloqueios. Não se apagam journals para trocar mapa ou
supor posição. O perfil legado e as suas migrações não foram recalibrados.

## Confirmações exatas no Orange Pi

1. Chip/canais e motores correspondentes já foram confirmados pelo teste
   relatado: direita/chip 0/canal 3 e esquerda/chip 0/canal 4, pela frente.
   Documentar imagem/kernel/overlays e identificar eletricamente conector,
   pad/pinmux, RX/TX e eventuais conflitos UART/console. RX/TX não são deduzidos
   desse teste e o cabeamento deve permanecer como está.
2. Registrar as permissões e exclusividade dos canais na instalação do serviço.
   O movimento observado não homologa por si só a operação concorrente,
   recuperação ou persistência do controller.
3. Medir e homologar período/polaridade e quatro larguras de pulso, em ns,
   correspondentes às poses esquerda 113°/5° e direita 70°/175°. Os 20 ms
   históricos e pulsos nominais antigos não são prova da calibração atual.
4. Confirmar fonte externa, GND comum, níveis elétricos e comportamento sob
   carga; definir ordem de abertura/fechamento, proteção contra obstrução,
   sustentação/torque e intervenção/parada segura.
5. Definir evidências reais de abertura, queda e retorno inicial, inclusive
   comportamento quando ausentes, e homologar sua correlação por ciclo/ID.
   Não foi afirmada existência de sensores. Tempo, escrita PWM e declaração de
   mão retirada não substituem evidência de movimento.
6. Integrar/homologar o provedor de evidências e o executor do plano antes de
   habilitar movimentos pelo backend; validar armazenamento, locks, falhas/restart
   e replay. Os testes reais já relatados não liberam automaticamente esse caminho.
   Preencher referências no JSON, sozinho, não satisfaz essas etapas.

## Validação pontual sem hardware — 10/11/2026

**77 aprovados, zero falhas/skips, 32,67 s.** Foram executados somente os testes
focados abaixo, em container efêmero da imagem de ferramentas existente, sem
rede/dispositivos, com checkout readonly e tmpfs temporário. As fixtures C
compilam seus binários como parte dos testes; nenhum build/deploy operacional.

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_project_mapping.py tests/test_c_controller_doorless.py tests/test_c_controller_physical.py tests/test_c_controller_operational.py --tb=short
```

Verificam o mapa atual C/Python sem RX/TX/pulsos presumidos, bloqueio físico,
snapshot imutável mesmo após configuração divergente, idempotência, retenção,
perfis históricos e estados indeterminados. Não foi executado hardware nesta
correção; o teste real dos motores é o relato do responsável registrado acima.
Nenhum schema, journal operacional, ID ou cabeamento foi alterado.

## Validação anterior sem hardware — 09/11/2026

Testes compilam as variantes C e o teste unitário nativo do driver; verificam
convenção do modelo, ausência de pulsos/pinmux presumidos, concordância do plano,
diagnóstico, encaminhamento explícito do JSON, conflitos de snapshot e bloqueio
mesmo com plano declarado. Regressões focadas conservam a cobertura dos journals,
falhas e fluxo sem porta. Resultado final: **280 aprovados, zero falhas/skips,
22,67 s**, com as variantes C compiladas usando `-std=c11 -Wall -Wextra -Werror
-Wno-unused-function -lsqlite3`. Formatação Python e `git diff --check` aprovados.

Comando focado, da pasta backend, em container efêmero da imagem de ferramentas
existente, sem rede/dispositivos, com checkout readonly e tmpfs temporário:

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_project_mapping.py tests/test_c_pwm_driver.py tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_operational.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py --tb=short
```

Sem alterações em frontend, IA, Supabase ou Docker; sem commit, push ou deploy.
