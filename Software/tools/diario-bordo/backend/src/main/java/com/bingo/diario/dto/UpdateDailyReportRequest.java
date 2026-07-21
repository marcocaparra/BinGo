package com.bingo.diario.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record UpdateDailyReportRequest(
        @NotBlank(message = "área é obrigatória")
        @Size(max = 80, message = "área deve ter no máximo 80 caracteres")
        String area,

        @NotBlank(message = "objetivo do dia é obrigatório")
        @Size(max = 160, message = "objetivo do dia deve ter no máximo 160 caracteres")
        String title,

        @NotBlank(message = "descrição é obrigatória")
        String description,

        @NotBlank(message = "problemas, dificuldades ou riscos são obrigatórios")
        String problems,

        String evidenceLinks,

        String participants,

        @NotBlank(message = "local ou ambiente é obrigatório")
        @Size(max = 120, message = "local ou ambiente deve ter no máximo 120 caracteres")
        String environment,

        @NotBlank(message = "tipo de registro é obrigatório")
        @Size(max = 80, message = "tipo de registro deve ter no máximo 80 caracteres")
        String recordType,

        @NotBlank(message = "decisões tomadas são obrigatórias")
        String decisions,

        @NotBlank(message = "testes, observações ou dados coletados são obrigatórios")
        String testsAndObservations,

        String toolsUsed,
        String pendingItems,
        String finalNotes) {
}
