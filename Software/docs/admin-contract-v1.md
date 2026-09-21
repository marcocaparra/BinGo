# Admin Web V1

Atualizado em: `2026-09-21`

Este documento define o funcionamento esperado do Admin Web do BinGo e as responsabilidades de cada classe de administrador. Ele descreve o que cada perfil pode consultar, criar, alterar ou operar dentro do ecossistema, sem definir detalhes de implementação do backend ou do banco de dados.

O Admin Web será uma aplicação única, com conteúdo e funcionalidades adaptados ao nível de acesso do administrador autenticado. As permissões descritas neste contrato devem ser respeitadas pelo backend independentemente do que estiver visível na interface.

## Visão geral

O Admin Web é a ferramenta utilizada para administrar o ecossistema BinGo e a operação das escolas participantes. Existem três classes de administrador: `ADMIN_A`, `ADMIN_B` e `ADMIN_C`. Cada uma representa uma responsabilidade diferente dentro do sistema.

O `ADMIN_A` pertence ao BinGo e possui visão global do ecossistema. Já `ADMIN_B` e `ADMIN_C` pertencem a uma escola específica. O `ADMIN_B` é a autoridade administrativa principal da escola, enquanto o `ADMIN_C` possui uma atuação mais operacional no dia a dia.

Todos os administradores acessam o mesmo sistema, mas não necessariamente os mesmos dados ou funcionalidades. Um administrador só pode realizar ações compatíveis com sua classe e, nos casos de `ADMIN_B` e `ADMIN_C`, com a escola à qual está vinculado.

## Classes de administrador

O `ADMIN_A` é o administrador global do BinGo. Ele não pertence a uma escola e é responsável por manter a estrutura geral do ecossistema. Pode criar escolas, administrar contas administrativas, cadastrar e acompanhar máquinas e Totens, controlar configurações econômicas globais e administrar as Missões globais do BinGo. Ele também pode auxiliar na implantação inicial de uma escola, criando sua estrutura, turmas e alunos quando necessário.

Apesar de possuir o maior nível de acesso estrutural, o `ADMIN_A` não participa da operação cotidiana das escolas. Ele não é responsável por aprovar uma troca de turma, entregar um produto do BinBazar ou resolver uma pendência individual de um aluno. Essas situações pertencem à equipe da própria escola.

O `ADMIN_B` é o administrador principal da escola. Pode haver mais de um `ADMIN_B` por escola. Ele é responsável por alunos, turmas, administradores de nível C, pendências escolares, BinBazar e resgates. É também o nível responsável por decisões administrativas que exigem autorização da escola, como a aprovação de uma solicitação de troca de turma.

O `ADMIN_C` é um administrador operacional da escola, como um orientador, coordenador, tutor ou outro funcionário autorizado. Ele possui acesso às informações necessárias para o trabalho diário, mas não pode alterar diretamente os dados administrativos dos alunos. Pode operar o BinBazar, atender resgates e solicitar mudanças que dependem da aprovação de um `ADMIN_B`.

As contas administrativas nunca são apagadas. Quando deixam de ter acesso, ficam inativas, preservando todo o histórico das ações realizadas. O `ADMIN_A` pode administrar as demais contas e o `ADMIN_B` pode administrar contas `ADMIN_C` da própria escola. Um administrador não pode desativar a própria conta, e o sistema deve sempre preservar pelo menos um `ADMIN_A` ativo.

## Dashboard e experiência administrativa

Todos os níveis administrativos acessam um dashboard após o login, mas o objetivo desse dashboard varia conforme a classe do usuário.

O dashboard do `ADMIN_A` possui uma visão global do BinGo. Ele deve priorizar informações como escolas cadastradas, administradores, máquinas e Totens, Missões globais, configurações do sistema e outras informações relevantes para a operação geral do ecossistema. O `ADMIN_A` não precisa receber uma fila de pendências cotidianas das escolas.

O dashboard do `ADMIN_B` é voltado à administração da própria escola. Ele deve facilitar o acesso aos alunos, turmas, administradores de nível C, pendências, produtos do BinBazar, estoque, resgates, Missões disponíveis e estado dos Totens da escola.

O dashboard do `ADMIN_C` é mais operacional. Ele deve facilitar tarefas como consultar alunos, solicitar troca de turma, acompanhar suas solicitações, administrar produtos e estoque do BinBazar, atender resgates e consultar o estado dos Totens.

A diferença entre os dashboards serve para organizar a experiência do usuário. Ela não substitui as regras de autorização do sistema.

## Administração da escola, alunos e turmas

O `ADMIN_A` pode participar da implantação e configuração estrutural de uma escola, mas a administração cotidiana dos alunos pertence principalmente ao `ADMIN_B`.

O `ADMIN_B` pode cadastrar alunos, criar e editar turmas, consultar os alunos da própria escola e alterar informações administrativas como nome, RA ou matrícula, turma e situação ativa ou inativa. Informações técnicas ou econômicas do sistema, como saldo de BinCoins, credenciais de autenticação e identificadores internos, não devem ser alteradas manualmente pelo administrador.

O RA ou matrícula deve identificar o aluno dentro da escola. O mesmo número pode existir em escolas diferentes, mas não deve existir para dois alunos da mesma escola.

O `ADMIN_C` pode consultar informações não confidenciais dos alunos da própria escola. Entre elas estão nome, email, RA ou matrícula, turma, status, saldo atual de BinCoins e XP atual da turma. Esse acesso é somente para consulta; o `ADMIN_C` não edita diretamente os dados do aluno.

Quando um aluno deixa de participar da operação da escola, ele deve ser marcado como inativo em vez de ser apagado. Seu histórico permanece preservado. Um aluno inativo não aparece normalmente para identificação no Totem, não realiza novos resgates e não utiliza normalmente sua conta autenticada no aplicativo. Caso realize um descarte sem identificação, o fluxo continua sendo tratado como descarte anônimo.

A criação de PIN e senha não faz parte da administração manual do aluno. O aluno pode existir previamente no sistema e, em seu processo de ativação, criar seu PIN no Totem e posteriormente vincular seu email e sua conta do aplicativo. O administrador não precisa criar uma senha individual para cada aluno.

### Troca de turma

O `ADMIN_B` pode alterar diretamente a turma de um aluno da própria escola. Já o `ADMIN_C` deve solicitar a mudança.

Ao solicitar uma troca, o `ADMIN_C` escolhe a turma de destino e cria uma pendência para os administradores `ADMIN_B` da escola. O aluno continua em sua turma atual até que um `ADMIN_B` aprove a solicitação.

Podem existir diferentes solicitações relacionadas ao mesmo aluno. Cabe ao `ADMIN_B` analisar o estado atual antes de aprovar qualquer uma delas. Uma solicitação antiga que deixou de fazer sentido não pode sobrescrever uma alteração mais recente do aluno.

O `ADMIN_C` pode cancelar uma solicitação própria enquanto ela ainda estiver pendente. Solicitações aprovadas, rejeitadas ou canceladas permanecem registradas como histórico.

## Pendências da escola

O Admin Web possui uma área de Pendências para concentrar situações que exigem atenção da equipe escolar. Essa área pode apresentar diferentes tipos de item, como solicitações de troca de turma e resgates do BinBazar.

O `ADMIN_B` visualiza as pendências operacionais da própria escola e é responsável pelas decisões administrativas que dependem de sua autorização. O `ADMIN_C` pode acompanhar as solicitações que criou e também visualizar as pendências operacionais que pode executar, como resgates do BinBazar.

O `ADMIN_A` não participa dessa fila. Ele pertence ao BinGo e não possui contexto presencial para decidir se um aluno mudou de turma, retirou determinado produto ou se existe estoque físico disponível na escola.

A área de Pendências pode crescer no futuro para incluir novos tipos de operação, mas cada processo continua seguindo suas próprias regras de negócio.

## BinBazar e resgates

O BinBazar é administrado localmente pela escola. Tanto `ADMIN_B` quanto `ADMIN_C` podem cadastrar produtos, editar suas informações, alterar preços, controlar estoque e ativar ou inativar produtos. Produtos não são apagados do sistema, pois podem estar ligados a resgates históricos.

O BinGo define um teto máximo de preço para os produtos. Esse teto é uma configuração global administrada pelo `ADMIN_A`. Os administradores da escola podem definir os preços de seus produtos desde que permaneçam dentro desse limite.

O estoque pode ser controlado pela escola ou tratado como ilimitado para determinados produtos. Caso um produto fique sem estoque, novos resgates não devem ser aceitos até que haja reposição. Um produto também pode ser inativado manualmente sem apagar seu histórico.

No V1, o aluno solicita o resgate pelo App Mobile. Assim que o pedido é aceito, os BinCoins necessários deixam de estar disponíveis para o aluno e, quando existe controle de estoque, a unidade correspondente também deixa de estar disponível. Isso impede que o mesmo saldo ou a mesma unidade seja utilizada em dois pedidos diferentes.

O pedido fica pendente até ser entregue ou cancelado. Não existe expiração automática no V1 e não existe um limite artificial de quantidade de pedidos; o limite natural é o saldo disponível do aluno e o estoque do produto.

Cada resgate possui um código que ajuda a escola a localizar o pedido. Esse código não é uma segunda autenticação. A entrega continua sendo uma operação humana: o responsável da escola consulta o pedido, confere as informações disponíveis do aluno, entrega o produto e marca o resgate como concluído.

`ADMIN_B` e `ADMIN_C` podem entregar ou cancelar resgates da própria escola. O próprio aluno também pode cancelar seu pedido pelo aplicativo enquanto ele ainda estiver pendente.

Quando um resgate é cancelado, os BinCoins cobrados devem retornar ao aluno e o estoque reservado deve ser restaurado. Quando ele é entregue, nenhuma nova cobrança é realizada, pois o valor já foi debitado no momento da solicitação.

Se uma tentativa de cancelamento acontecer ao mesmo tempo em que a escola confirma a entrega, apenas uma das duas operações pode ser concluída. Um pedido já entregue não pode ser cancelado posteriormente.

Alterações posteriores no produto não modificam um resgate antigo. O sistema deve preservar a informação necessária para que o histórico continue representando corretamente qual produto foi solicitado e qual valor foi cobrado no momento do pedido.

## Administração global do BinGo

Além da gestão de contas e escolas, o `ADMIN_A` é responsável pelas funções que pertencem ao ecossistema como um todo.

Máquinas e Totens são administrados pelo `ADMIN_A`. Ele pode cadastrá-los, vinculá-los às escolas e controlar sua situação operacional. `ADMIN_B` e `ADMIN_C` podem consultar o estado dos equipamentos da própria escola, mas não possuem acesso às credenciais técnicas utilizadas pelas máquinas.

O `ADMIN_A` também pode administrar configurações econômicas do BinGo, como os valores-base utilizados na pontuação, metas configuráveis, taxas de bônus por categoria ambiental e o teto de preço do BinBazar. Alterações nessas configurações não devem modificar operações que já aconteceram anteriormente.

As definições e ciclos globais de Missões também são administrados pelo `ADMIN_A`. `ADMIN_B` e `ADMIN_C` podem consultar as Missões relacionadas à escola, mas não criam novas Missões no V1. Uma evolução futura poderá permitir que `ADMIN_B` crie Missões específicas da própria escola, porém essa funcionalidade não faz parte da primeira versão.

Ações relevantes realizadas pelos administradores devem permanecer registradas para auditoria. Isso inclui alterações administrativas, criação ou inativação de contas, mudanças de turma, decisões sobre solicitações, operações de resgate, alterações de produtos, configurações globais e administração de máquinas.

## Limites do V1

O Admin Web V1 prioriza as operações necessárias para o funcionamento atual do BinGo e das feiras. Funcionalidades que adicionam complexidade sem necessidade imediata devem permanecer fora desta primeira versão.

Não fazem parte do V1 mecanismos como aprovação de novas contas administrativas, convite obrigatório por email, recuperação administrativa personalizada de senha, QR obrigatório para retirada de produto, PIN de confirmação de resgate, expiração automática de pedidos ou criação de Missões próprias pelo `ADMIN_B`.

Essas funcionalidades podem ser adicionadas futuramente sem alterar a divisão fundamental de responsabilidades entre `ADMIN_A`, `ADMIN_B` e `ADMIN_C`.

O objetivo desta primeira versão é manter uma divisão clara: o `ADMIN_A` administra o BinGo, o `ADMIN_B` administra a escola e o `ADMIN_C` executa as operações escolares que lhe foram delegadas.