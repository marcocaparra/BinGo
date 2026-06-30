# Totem Kiosk Wireframe

Wireframe visual navegável para o Totem BinGo em tela touch vertical de 7 polegadas.

## Objetivo

Este protótipo usa a lógica das telas antigas de `UX e Design/UI e Telas`, mas segue a linguagem visual do app mobile atual. Ele existe para revisão rápida de fluxo e interface antes da implementação real do kiosk no Orange Pi com Ubuntu.

## Como abrir

Sirva a pasta `Software` como raiz estatica:

```bash
cd Software
python -m http.server 8092 --bind 127.0.0.1
```

Abra:

```text
http://127.0.0.1:8092/apps/totem_kiosk_wireframe/
```

Se a porta `8092` ja estiver ocupada, use outra porta e mantenha o mesmo caminho `/apps/totem_kiosk_wireframe/`.

## Escopo

- Fluxo vertical para tela de 7 polegadas.
- B1N como fonte principal das instruções: as frases operacionais aparecem como fala dele.
- Estado idle de kiosk com B1N aguardando/dormindo, sem balão de fala.
- Tela de PIN com B1N em postura de privacidade.
- Login por aluno/turma/PIN como wireframe.
- Opção de pontuar apenas para turma.
- Escolha de categoria do item.
- Checagem de segurança para pilhas, baterias e celulares.
- Estados de inserir, analisar, sucesso e chamar professor.

## Fora do escopo

- Backend real.
- Câmera/visão computacional real.
- Edge local do Orange Pi.
- Persistência de dados.
- Integração com Supabase ou FastAPI.

## Diretriz visual do B1N

- Evitar textos longos soltos na tela; quando for instrução, deve parecer fala do B1N.
- No estado parado, o totem deve parecer aguardando toque, nao vendendo uma mensagem.
- Na etapa de PIN, o B1N deve reforçar privacidade visualmente. O asset ideal futuro é uma pose com olhos fechados ou virado discretamente para o lado.
- Em etapas em que o B1N já aparece grande, ele pode ocupar mais área visual e a fala deve ficar curta para não poluir a tela de 7 polegadas.
