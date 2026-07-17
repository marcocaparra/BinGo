package com.bingo.diario.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.bingo.diario.dto.AuthRole;
import com.bingo.diario.exception.UnauthorizedException;

@Service
public class AccessTokenService {

    private static final String HMAC_ALGORITHM = "HmacSHA256";

    private final byte[] signingSecret;
    private final Duration tokenTtl;
    private final Clock clock;

    public AccessTokenService(
            @Value("${app.auth.signing-secret}") String signingSecret,
            @Value("${app.auth.token-ttl-hours:8}") long tokenTtlHours,
            Clock clock) {
        if (signingSecret == null || signingSecret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalArgumentException("O segredo de assinatura deve ter pelo menos 32 caracteres.");
        }
        this.signingSecret = signingSecret.getBytes(StandardCharsets.UTF_8);
        this.tokenTtl = Duration.ofHours(tokenTtlHours);
        this.clock = clock;
    }

    public IssuedToken issue(AuthRole role) {
        Instant expiresAt = Instant.now(clock).plus(tokenTtl);
        String payload = role.name() + "." + expiresAt.getEpochSecond() + "."
                + UUID.randomUUID().toString().replace("-", "");
        return new IssuedToken(payload + "." + sign(payload), expiresAt);
    }

    public AuthRole validateAuthorization(String authorization) {
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            throw new UnauthorizedException("Sessão ausente ou inválida.");
        }

        String token = authorization.substring("Bearer ".length()).trim();
        String[] parts = token.split("\\.", -1);
        if (parts.length != 4) {
            throw new UnauthorizedException("Sessão ausente ou inválida.");
        }

        String payload = parts[0] + "." + parts[1] + "." + parts[2];
        byte[] providedSignature;
        byte[] expectedSignature;
        try {
            providedSignature = Base64.getUrlDecoder().decode(parts[3]);
            expectedSignature = Base64.getUrlDecoder().decode(sign(payload));
        } catch (IllegalArgumentException exception) {
            throw new UnauthorizedException("Sessão ausente ou inválida.");
        }

        if (!MessageDigest.isEqual(providedSignature, expectedSignature)) {
            throw new UnauthorizedException("Sessão ausente ou inválida.");
        }

        try {
            AuthRole role = AuthRole.valueOf(parts[0]);
            Instant expiresAt = Instant.ofEpochSecond(Long.parseLong(parts[1]));
            if (!expiresAt.isAfter(Instant.now(clock))) {
                throw new UnauthorizedException("Sua sessão expirou. Entre novamente.");
            }
            return role;
        } catch (IllegalArgumentException exception) {
            throw new UnauthorizedException("Sessão ausente ou inválida.");
        }
    }

    private String sign(String payload) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(new SecretKeySpec(signingSecret, HMAC_ALGORITHM));
            return Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception exception) {
            throw new IllegalStateException("Não foi possível assinar a sessão.", exception);
        }
    }

    public record IssuedToken(String value, Instant expiresAt) {
    }
}
