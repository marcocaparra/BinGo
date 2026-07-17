# Fluxo do frontend

## Fluxo principal

```text
Preparação da API -> Perfil -> PIN de seis dígitos -> Seleção do integrante
                                                     |
                                                     v
                                              Relatório do dia
                                              |              |
                                              v              v
                                       Registrar         Sem atividade
                                              |              |
                                              +------v-------+
                                                     |
                                                     v
                                             Confirmação e histórico
```

Se o backend gratuito estiver suspenso, a abertura mostra `Preparando o Diário
de Bordo...` e repete o health check em intervalos progressivos. Depois de 45
segundos, a pessoa pode tentar novamente sem recarregar a página.

## Regras de interface

- A sessão fica apenas no `sessionStorage` e termina ao fechar o navegador ou após oito horas.
- A data máxima de preenchimento e filtros é o dia atual.
- O envio tem confirmação visual e proteção contra cliques repetidos.
- A equipe registra evidências como texto e links na publicação inicial.
- A coordenação pode filtrar, editar, excluir e exportar registros em Markdown.
- Excluir um registro permite que o integrante preencha novamente aquela data.
- Uploads ficam ocultos enquanto `VITE_ATTACHMENTS_ENABLED=false`.

## Permissões

- **Equipe:** integrantes, preenchimento e histórico permitido pela API.
- **Coordenação:** painel, pendências, edição, exclusão e exportação.

Anexos persistentes poderão ser reativados em uma segunda etapa com um storage
externo; o disco temporário do Koyeb não deve ser usado para arquivos.
