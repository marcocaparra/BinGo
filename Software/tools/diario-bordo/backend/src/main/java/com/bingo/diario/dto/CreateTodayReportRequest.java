package com.bingo.diario.dto;

import java.time.LocalDate;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

public record CreateTodayReportRequest(
        @NotNull(message = "integrante é obrigatório")
        UUID memberId,

        @NotNull(message = "data do relatório é obrigatória")
        LocalDate reportDate,

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

        String solution,
        String nextSteps,

        String evidenceLinks,

        @PositiveOrZero(message = "tempo gasto deve ser maior ou igual a zero")
        Integer timeSpentMinutes,

        @Size(max = 40, message = "tempo aproximado deve ter no máximo 40 caracteres")
        String approximateTime,

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

        @Size(max = 120, message = "responsável pelo próximo passo deve ter no máximo 120 caracteres")
        String nextStepOwner,

        LocalDate nextStepDueDate,
        String finalNotes) {
}
