package com.bingo.diario.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import org.junit.jupiter.api.Test;

import com.bingo.diario.dto.AuthRole;
import com.bingo.diario.exception.UnauthorizedException;

class AccessTokenServiceTest {

    private static final String SECRET = "test-signing-secret-with-at-least-32-characters";

    @Test
    void validatesSignedTokenAndRejectsItAfterExpiration() {
        Instant issuedAt = Instant.parse("2026-07-14T12:00:00Z");
        AccessTokenService issuer = serviceAt(issuedAt);
        AccessTokenService.IssuedToken token = issuer.issue(AuthRole.ADMIN);

        assertThat(issuer.validateAuthorization("Bearer " + token.value())).isEqualTo(AuthRole.ADMIN);

        AccessTokenService expiredValidator = serviceAt(issuedAt.plusSeconds(8 * 60 * 60L + 1));
        assertThatThrownBy(() -> expiredValidator.validateAuthorization("Bearer " + token.value()))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("expirou");
    }

    @Test
    void rejectsTamperedTokens() {
        AccessTokenService service = serviceAt(Instant.parse("2026-07-14T12:00:00Z"));
        String token = service.issue(AuthRole.TEAM).value();

        assertThatThrownBy(() -> service.validateAuthorization("Bearer " + token + "x"))
                .isInstanceOf(UnauthorizedException.class);
    }

    private AccessTokenService serviceAt(Instant instant) {
        return new AccessTokenService(SECRET, 8, Clock.fixed(instant, ZoneOffset.UTC));
    }
}
