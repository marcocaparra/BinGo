package com.bingo.diario.dto;

import java.util.UUID;

import jakarta.validation.constraints.NotNull;

public record CreateNoActivityReportRequest(
        @NotNull(message = "memberId é obrigatório")
        UUID memberId) {
}
