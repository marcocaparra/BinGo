# Fluxo do Ecossistema de Descarte — BinGo V1

Este documento descreve o fluxo de descarte de lixo eletrônico da primeira versão oficial do BinGo, envolvendo o aluno, o Totem, o Hardware, o sistema de visão computacional, o Gemini e o Backend. O objetivo principal do fluxo é permitir que um aluno descarte um lixo eletrônico de forma orientada, receba pontos pela ação e tenha o descarte registrado em seu histórico.

Na regra-alvo da primeira versão, todos os descartes válidos partem da mesma recompensa-base: `800` BinCoins para o aluno identificado e `1900` XP para a turma. Esses valores são a redenominação oficial por fator `100` das antigas unidades `8` e `19`; preservam a mesma relação econômica e devem ser usados como unidade real pelo domínio, backend, banco, APIs, Admin e Mobile, sem multiplicação apenas visual no frontend. A categoria canônica pode acrescentar um bônus percentual somente aos BinCoins, sem multiplicar a taxa nem alterar o XP. Ela também serve para exibição, histórico, estatísticas e avaliação da visão computacional; tamanho físico não participa do cálculo. A conversão está versionada e validada localmente em migration coordenada; este documento não declara ambiente hospedado ou produção já convertido.

## Fluxo principal

O fluxo começa quando o aluno chega ao Totem e inicia uma sessão de descarte. Antes de permitir o início da operação, o Totem deve estar conectado à internet e possuir acesso aos serviços necessários, como o Backend e a visão computacional. O BinGo não permitirá o início de novos descartes sem conexão. Quando estiver sem internet ou sem acesso aos serviços obrigatórios, o Totem deverá entrar em modo fora de operação e apresentar uma mensagem de indisponibilidade.

Após iniciar a sessão, o aluno deverá se identificar pelo método definido para o Totem. O sistema deverá associar todo o ciclo de descarte ao aluno identificado e criar um identificador único para aquela operação. Esse identificador deverá ser reutilizado durante todo o fluxo para impedir que repetições de requisições, cliques duplicados, timeouts ou falhas de comunicação gerem mais de um descarte ou mais de uma pontuação.

Antes da abertura da porta, o Totem poderá apresentar uma triagem de segurança para verificar se o objeto possui sinais visíveis de risco, como vazamento, estufamento, partes cortantes, líquidos ou danos que possam representar perigo. Caso o aluno informe que o objeto apresenta risco, o descarte automático não deverá continuar, e o Totem deverá orientar o aluno a procurar um responsável.

Caso o descarte possa continuar, o Totem enviará ao Hardware o comando para abrir a porta de entrada. Depois da abertura, o aluno deverá inserir o lixo eletrônico no compartimento. A orientação oficial da primeira versão será inserir apenas um item por ciclo de descarte.

O sistema não possuirá sensor nem análise visual para detectar se a mão do aluno ainda está dentro do compartimento. Por isso, depois de inserir o objeto, o próprio aluno deverá retirar a mão e pressionar um botão com uma mensagem semelhante a &#x2A;*“Retirei a mão”**. O pressionamento desse botão representa uma declaração do usuário e autoriza o fechamento da porta.

Como o sistema não verificará tecnicamente a presença da mão, a segurança desse movimento deverá ser garantida principalmente pelo projeto mecânico da porta, pela limitação de força, pela velocidade de fechamento e pelas proteções físicas definidas pela equipe de Hardware.&#x20;

Depois que o aluno confirmar a retirada da mão, o Totem enviará ao Hardware o comando de fechamento. Quando a porta estiver fechada, a câmera capturará uma imagem do conteúdo do compartimento e a enviará ao classificador principal de visão computacional.

O classificador deverá determinar se o objeto pertence ou não ao domínio de lixo eletrônico. A resposta poderá representar um lixo eletrônico reconhecido, um objeto que não é lixo eletrônico ou um resultado incerto. Além dessa decisão, o classificador poderá retornar uma classe principal e outras classes candidatas encontradas durante a análise.

Quando o classificador principal determinar com confiança que o objeto não é um lixo eletrônico, o descarte será recusado. O Totem deverá informar o problema ao aluno, reabrir a porta e solicitar a retirada do objeto. Nenhum descarte será registrado e nenhum ponto será concedido.

Quando o resultado do classificador principal for incerto, inconclusivo ou possuir confiança insuficiente, a imagem será enviada ao Gemini para uma segunda análise. O Gemini funcionará apenas como mecanismo de apoio para casos incertos e não será chamado quando o classificador principal já apresentar uma resposta considerada suficientemente confiável.

Depois da análise do Gemini, o fluxo poderá seguir como lixo eletrônico reconhecido, objeto não eletrônico ou resultado ainda inconclusivo. Caso a análise secundária determine que não se trata de lixo eletrônico, o objeto deverá ser devolvido ao aluno sem geração de pontos.

Quando o sistema concluir que o objeto é um lixo eletrônico, o Totem apresentará ao aluno a classe considerada mais provável. O aluno poderá confirmar que a identificação está correta ou informar que o objeto foi identificado incorretamente.

Caso o aluno confirme a identificação, o fluxo seguirá normalmente. Caso informe que a identificação está errada, o Totem deverá apresentar a lista de classes retornadas pela visão computacional. Essa lista não deverá exibir o JSON bruto nem informações técnicas internas. A interface mostrará os nomes das classes de forma organizada e compreensível para que o aluno possa verificar se o objeto correto está entre as opções encontradas pelo modelo.

Se o aluno encontrar a classe correta, poderá selecioná-la e continuar o descarte. A resposta original da visão computacional e a classe escolhida pelo aluno deverão ser mantidas nos registros de auditoria, permitindo avaliar posteriormente os erros e acertos do modelo.

Caso o aluno não encontre o objeto na lista, poderá selecionar a opção &#x2A;*“Lixo eletrônico não identificado”**. Essa opção representa um objeto que foi reconhecido como pertencente ao domínio de lixo eletrônico, mas cuja classe exata não pôde ser determinada.

Um lixo eletrônico não identificado poderá ser descartado normalmente sob a categoria canônica `UNKNOWN`, com origem `UNIDENTIFIED`. Ele recebe a recompensa-base e bônus zero. A ausência da classe exata não interfere na validade do descarte, e o histórico poderá apresentar “Lixo eletrônico não identificado”.

A opção de lixo eletrônico não identificado somente deverá estar disponível quando o sistema já tiver concluído que o objeto pertence ao domínio de lixo eletrônico. Ela não poderá ser utilizada para transformar manualmente um objeto claramente classificado como não eletrônico em um descarte válido.

Depois da confirmação da classe ou da seleção da opção de lixo eletrônico não identificado, o Totem enviará ao Hardware o comando para executar o descarte físico. A escotilha inferior será aberta para permitir que o objeto caia no compartimento interno de armazenamento.

Caso não exista um sensor capaz de confirmar fisicamente a queda do objeto, o descarte será considerado fisicamente concluído após o Hardware confirmar que o ciclo mecânico esperado foi executado, incluindo a abertura da escotilha, o tempo necessário para a queda, o fechamento da escotilha e o retorno dos mecanismos ao estado inicial.

Após a conclusão do ciclo mecânico, o Totem enviará ao Backend a saída observada pela visão, a categoria canônica final e sua origem. O Backend deverá registrar o descarte, calcular a base e o bônus ambiental server-side e associar o evento ao histórico do aluno.

O registro do descarte e a geração dos pontos deverão ser idempotentes. Isso significa que o mesmo identificador de ciclo poderá ser enviado novamente em caso de timeout ou falha de comunicação, mas o Backend continuará produzindo apenas um descarte e um lançamento de pontos.

Depois que o Backend confirmar o registro, o Totem apresentará uma mensagem de sucesso ao aluno, informando que o lixo eletrônico foi recebido e que os pontos foram adicionados. Em seguida, a sessão será encerrada, os dados temporários do aluno serão removidos da interface e o Totem retornará à tela inicial.

## Quantidade de objetos

A primeira versão orientará o descarte de apenas um item por vez, mas o sistema de visão computacional não será responsável por detectar quantidades.

Caso o aluno insira vários objetos iguais e a visão computacional reconheça apenas uma classe, o ciclo será registrado como um único descarte. O aluno receberá pontos apenas uma vez e haverá somente uma entrada no histórico.

Essa limitação deverá ser comunicada claramente na interface do Totem. O aluno deverá ser instruído a inserir somente um item, mesmo que o sistema não possua uma forma técnica de impedir ou detectar com precisão a inserção de vários objetos.

O comportamento para vários objetos de classes diferentes ainda deverá ser definido antes da implementação definitiva. A visão computacional poderá retornar mais de uma classe, considerar o resultado incerto ou priorizar apenas um dos objetos presentes. Essa situação não deverá ser resolvida implicitamente pelo Backend ou pela interface sem uma regra de negócio aprovada.

## Conectividade e falhas

O descarte depende de conexão com a internet porque a classificação do objeto utiliza serviços externos ou remotos de visão computacional. Por esse motivo, o Totem não realizará novos descartes offline.

Antes de iniciar uma sessão, o sistema deverá verificar a disponibilidade dos serviços obrigatórios. Caso algum serviço esteja indisponível, a porta não deverá ser aberta e o Totem entrará em modo fora de operação.

Também deverá existir tratamento para perda de conexão durante uma sessão. Se a conexão cair antes da execução do descarte físico, o sistema deverá interromper o fluxo com segurança e permitir que o aluno recupere o objeto.

Se a conexão cair depois que o objeto já tiver sido liberado para o compartimento interno, o descarte físico não poderá ser desfeito. Nesse caso, deverá existir um mecanismo de recuperação para que o evento já concluído não seja perdido e possa ser enviado ao Backend quando a comunicação for restabelecida.

Esse mecanismo de recuperação não representa operação offline. Ele serve apenas para preservar um descarte que começou com o Totem online e cuja etapa física foi concluída antes da falha de comunicação.

Falhas mecânicas, como porta que não abre, porta que não fecha, escotilha travada ou ausência de confirmação do Arduino, deverão interromper o fluxo. O Totem não poderá registrar sucesso nem conceder pontos enquanto o ciclo físico não tiver sido concluído conforme as confirmações disponíveis.

Quando uma falha deixar o estado físico do equipamento indefinido, o Totem deverá bloquear novos descartes, apresentar uma mensagem de indisponibilidade e aguardar recuperação automática ou intervenção de um responsável.

## Regras gerais da primeira versão

Cada ciclo do Totem poderá gerar no máximo um descarte e uma pontuação. Objetos recusados, operações canceladas e ciclos mecânicos não concluídos não gerarão pontos.

Todos os lixos eletrônicos aceitos possuirão a mesma recompensa-base. A categoria do objeto poderá acrescentar bônus somente aos BinCoins; o XP da turma permanecerá igual para todo descarte válido.

O Gemini será utilizado somente como análise secundária para resultados incertos do classificador principal.

O aluno poderá corrigir a classe sugerida pela inteligência artificial ou selecionar lixo eletrônico não identificado quando o sistema já tiver confirmado que o objeto pertence ao domínio de lixo eletrônico.

A V1 não realizará detecção automática de quantidade nem detecção da presença da mão. A retirada da mão será confirmada pelo próprio aluno por meio de um botão.

O Totem não iniciará descartes sem conexão com a internet. Falhas ocorridas durante um ciclo deverão conduzir o equipamento a uma recuperação segura, sempre considerando a posição física do objeto.

O Backend deverá impedir eventos e pontuações duplicadas, mesmo quando o Totem repetir uma requisição.

O fluxo geral da primeira versão pode ser resumido da seguinte forma:

**Aluno inicia e se identifica → Totem verifica segurança e conectividade → porta abre → aluno insere o objeto → aluno retira a mão e confirma no botão → porta fecha → visão computacional analisa → Gemini é acionado somente se o resultado for incerto → aluno confirma ou corrige a identificação → objeto é descartado → Backend registra o evento e os pontos → Totem apresenta sucesso e encerra a sessão.**
