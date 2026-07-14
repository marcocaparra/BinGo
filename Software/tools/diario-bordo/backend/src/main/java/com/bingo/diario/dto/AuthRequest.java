package com.bingo.diario.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

public record AuthRequest(
        @NotNull(message = "tipo de acesso é obrigatório")
        AuthRole role,

        @NotBlank(message = "PIN é obrigatório")
        @Pattern(regexp = "\\d{4}", message = "PIN deve ter 4 dígitos")
        String pin) {
}
