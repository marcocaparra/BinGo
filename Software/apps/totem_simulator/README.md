# Totem Simulator

O Totem Simulator é uma interface web simples para simular o fluxo inicial de descarte do totem BinGo.

Esta versão é apenas visual e interativa. Ela não usa backend, banco de dados, Supabase, autenticação real, câmera, IA, Arduino, Docker, migrations ou chamadas HTTP.

## Como abrir localmente

Abra o arquivo `index.html` diretamente no navegador:

```text
apps/totem_simulator/index.html
```

Não existe etapa de build ou instalação de dependências.

## Páginas disponíveis

- **Simulador de descarte**: permite escolher aluno, tamanho do item, validade e tipo detectado. Descartes válidos geram Bins localmente.
- **Informações do aluno**: mostra saldo atual, turma, descartes válidos, descartes inválidos, total gerado e último descarte.
- **Rankings**: exibe ranking de alunos e turmas, ordenado do maior para o menor saldo.

## Dados mockados

Os dados ficam em memória no arquivo `app.js`:

- Escola Demo BinGo
- Turmas: 6º Ano A, 7º Ano B e 1ª Série A
- Alunos: Ana Silva, Pedro Santos, João Teste, Maria Oliveira e Lucas Costa
- Pontuação inicial de alunos e turmas
- Histórico local de descartes simulados

Ao atualizar a página, os dados voltam ao estado inicial.

## Regra de pontuação simulada

- SMALL: 10 Bins
- MEDIUM: 25 Bins
- LARGE: 50 Bins

Itens inválidos não geram Bins.

## Próximo passo futuro

Integrar esta interface com o backend real do BinGo para registrar depósitos, validar eventos e atualizar saldos reais de alunos e turmas.
