package com.bingo.diario.dto;

import java.time.LocalDate;
import java.util.UUID;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public record CreateNoActivityReportRequest(
        @NotNull(message = "memberId é obrigatório")
        UUID memberId,

        @NotNull(message = "data do relatório é obrigatória")
        LocalDate reportDate,

        @Size(max = 80, message = "área deve ter no máximo 80 caracteres")
        String area) {
}
