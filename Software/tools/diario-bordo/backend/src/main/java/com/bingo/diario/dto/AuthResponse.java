package com.bingo.diario.dto;

import java.time.Instant;

public record AuthResponse(AuthRole role, String token, Instant expiresAt) {
}
