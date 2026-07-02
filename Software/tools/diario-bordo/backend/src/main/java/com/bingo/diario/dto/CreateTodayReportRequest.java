package com.bingo.diario.dto;

import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

public record CreateTodayReportRequest(
        @NotNull(message = "memberId é obrigatório")
        UUID memberId,

        @NotBlank(message = "area é obrigatória")
        @Size(max = 80, message = "area deve ter no máximo 80 caracteres")
        String area,

        @NotBlank(message = "title é obrigatório")
        @Size(max = 160, message = "title deve ter no máximo 160 caracteres")
        String title,

        @NotBlank(message = "description é obrigatória")
        String description,

        String problems,
        String solution,
        String nextSteps,
        String evidenceLinks,

        @PositiveOrZero(message = "timeSpentMinutes deve ser maior ou igual a zero")
        Integer timeSpentMinutes) {
}
