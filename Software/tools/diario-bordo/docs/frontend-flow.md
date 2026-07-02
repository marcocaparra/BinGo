# Fluxo previsto do frontend

O frontend será implementado depois da base do backend. Este fluxo define
apenas as telas e interações necessárias para a V1.

## Fluxo principal

```text
Acesso com senha coletiva
        |
        v
Seleção do integrante
        |
        v
Relatório do dia
   |             |
   v             v
Registrar      Marcar "não fiz
atividade      atividade hoje"
   |             |
   +------v------+
          |
          v
Confirmação e histórico
```

## Telas mínimas

1. **Acesso:** solicita a senha coletiva e informa quando ela for inválida.
2. **Seleção de integrante:** exibe apenas integrantes ativos e você seleciona seu usuário.
3. **Relatório do dia:** coleta área, título, descrição e campos opcionais.
4. **Histórico:** lista relatórios e oferece filtros por integrante, área,
   data e status.
5. **Pendências:** mostra integrantes os relatórios de certos dias que não foram preenchidos.
6. **Configurações:** inicial onde o usuário pode adicionar integrantes (futuramente podem haver novas alterações).

## Regras de interface

- A data de hoje deve ser exibida, mas não editada pelo usuário.
- O envio precisa de confirmação visual e proteção contra cliques repetidos.
- Ao receber conflito de duplicidade, a interface deve orientar a editar o
  relatório existente.
- O registro de `NO_ACTIVITY` deve pedir confirmação.
- Links de evidência devem ser validados como URLs.

## Fora da primeira etapa

- upload de imagens ou arquivos;
- exportação para `.xlsx`;
- gerenciamento avançado de usuários ou permissões.
