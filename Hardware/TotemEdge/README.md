# BinGo Totem Edge

Esta pasta reúne os componentes de software executados localmente no Orange Pi do Totem BinGo.

O Totem Edge funciona como a camada local responsável por integrar a interface do usuário, os dispositivos físicos do Totem, a câmera e o backend remoto do BinGo.

O frontend não deve acessar diretamente motores, sensores, câmera ou o backend remoto. Essas integrações são intermediadas pelo software executado no Orange Pi.

## Estrutura

```text
TotemEdge/
├── backend/
├── camera/
├── controller/
├── deploy/
├── frontend/
└── README.md
```

## backend/

Serviço local principal do Totem, desenvolvido em Python com FastAPI.
É responsável por orquestrar o funcionamento do Totem e servir como ponto de comunicação entre o frontend e os demais componentes locais.
Entre suas responsabilidades estão:
- disponibilizar a API local utilizada pelo frontend;
- controlar o estado e o fluxo das sessões do Totem;
- integrar os componentes de câmera e controle físico;
- realizar chamadas ao backend remoto do BinGo;
- tratar conectividade, erros e recuperação de operações;
- manter dados locais necessários para funcionamento e recuperação do Totem.
As regras de negócio definitivas, como pontuação, saldo e persistência oficial de descartes, continuam sendo responsabilidade do backend central.

## controller/

Código responsável pela comunicação com os componentes físicos conectados ao Orange Pi.
Essa camada poderá controlar, por exemplo:
- motores;
- LEDs;
- sensores;
- relés;
- GPIOs;
- demais atuadores utilizados pelo Totem.
A implementação poderá utilizar a linguagem ou biblioteca mais adequada ao hardware utilizado.
O restante do sistema deve utilizar esta camada para interagir com os dispositivos físicos, evitando espalhar código específico de GPIO ou controle de hardware pelo projeto.

## camera/

Código responsável pela integração com a câmera instalada no Totem.
Essa camada deverá concentrar funcionalidades relacionadas a:
- inicialização e encerramento da câmera;
- disponibilização do preview para a interface;
- captura de imagens;
- acesso às imagens utilizadas pelo sistema de visão computacional.
O frontend poderá exibir a imagem da câmera, mas não deverá controlar diretamente o dispositivo.

## frontend/

Interface web executada no modo kiosk do Totem.
É responsável pela interação com o aluno e pela apresentação dos estados do fluxo.
O frontend comunica as ações do usuário ao backend local e apresenta as respostas recebidas.
Ele não deve acessar diretamente:
- GPIO;
- motores;
- sensores;
- câmera;
- serviços de visão computacional;
- credenciais da máquina;
- backend remoto do BinGo.

## deploy/

Arquivos relacionados à instalação e execução do Totem no Orange Pi.
Esta pasta poderá futuramente conter:
- configurações de Docker;
- arquivos de serviço do systemd;
- scripts de instalação;
- scripts de inicialização;
- configurações específicas do ambiente do Orange Pi.
A estratégia definitiva de deploy ainda será definida conforme a integração com o hardware real.
Princípio geral
A divisão de responsabilidades do Totem Edge segue este modelo:
```
Frontend
   ↓
Backend local
   ├── Controller
   ├── Camera
   └── Backend remoto
```
O frontend representa a interação do usuário.
O backend local controla o fluxo do Totem.
Os módulos de controller e camera integram o Orange Pi aos dispositivos físicos.
O backend remoto continua sendo a fonte de verdade para os dados e regras de negócio oficiais do BinGo.

## Princípio geral

A divisão de responsabilidades do Totem Edge segue este modelo:
```
Frontend
   ↓
Backend local
   ├── Controller
   ├── Camera
   └── Backend remoto
```
O frontend representa a interação do usuário.
O backend local controla o fluxo do Totem.
Os módulos de controller e camera integram o Orange Pi aos dispositivos físicos.
O backend remoto continua sendo a fonte de verdade para os dados e regras de negócio oficiais do BinGo.
