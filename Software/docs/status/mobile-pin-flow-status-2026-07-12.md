# Mobile PIN Flow Status - 2026-07-12

## Estado

Implementado na branch `feature/mobile-pin-refresh`.

## Entrega

- Novo hub de acesso com `Criar meu PIN`, `Ja tenho PIN` e acesso secundario ao modo piloto.
- Cadastro guiado: escola, nome ou matricula, PIN de quatro digitos e confirmacao.
- Login local e redefinicao do PIN pelo mesmo conjunto de dados.
- Persistencia de demonstracao com `shared_preferences`; os dados ficam somente neste dispositivo ou navegador.
- Novo sistema de botao compartilhado com brilho superior, profundidade, estado pressionado e variante secundaria/discreta.
- B1N contextual no acesso, privacidade do PIN, duvida e confirmacao.

## Assets adicionados ao app

As copias para `Software/mobile/bingo_app/assets/images/` vieram da biblioteca oficial de poses:

- `b1n_ideia_instrucao_web.png`
- `b1n_privacidade_pin_olhos_fechados_web.png`
- `b1n_joinha_confirmacao_web.png`
- `b1n_segurando_bincoin_recompensa_web.png`
- `b1n_duvida_pergunta_web.png`

## Limites atuais

- O PIN local nao e autenticacao de producao e nao deve ser tratado como mecanismo de seguranca real.
- O backend futuro deve substituir apenas `ProfileRepository`; a interface e as telas podem permanecer.
- A proxima rodada prevista e a revisao de conteudo e layout de Inicio, Carteira/BinBazar, Missoes, Ranking e Perfil.

## Validacao executada

```powershell
flutter analyze
flutter test
flutter build web
```

Resultado desta rodada: analise sem problemas e 15 testes passando.
