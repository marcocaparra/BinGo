package com.bingo.diario.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.bingo.diario.dto.AuthResponse;
import com.bingo.diario.dto.AuthRole;
import com.bingo.diario.exception.UnauthorizedException;

@Service
public class AuthService {

    private final String teamPin;
    private final String adminPin;
    private final AccessTokenService tokenService;
    private final AuthRateLimiter rateLimiter;

    public AuthService(
            @Value("${app.auth.team-pin}") String teamPin,
            @Value("${app.auth.admin-pin}") String adminPin,
            AccessTokenService tokenService,
            AuthRateLimiter rateLimiter) {
        if (!teamPin.matches("\\d{6}") || !adminPin.matches("\\d{6}")) {
            throw new IllegalArgumentException("Os PINs devem ter exatamente seis dígitos.");
        }
        if (teamPin.equals(adminPin)) {
            throw new IllegalArgumentException("Os PINs da equipe e da coordenação devem ser diferentes.");
        }
        this.teamPin = teamPin;
        this.adminPin = adminPin;
        this.tokenService = tokenService;
        this.rateLimiter = rateLimiter;
    }

    public AuthResponse authenticate(AuthRole requestedRole, String pin, String clientKey) {
        String rateLimitKey = clientKey;
        rateLimiter.requireAllowed(rateLimitKey);

        boolean valid = requestedRole == AuthRole.ADMIN ? isAdminPin(pin) : isTeamPin(pin);
        if (!valid) {
            rateLimiter.recordFailure(rateLimitKey);
            throw new UnauthorizedException("PIN inválido.");
        }

        rateLimiter.clear(rateLimitKey);
        AccessTokenService.IssuedToken issuedToken = tokenService.issue(requestedRole);
        return new AuthResponse(requestedRole, issuedToken.value(), issuedToken.expiresAt());
    }

    public void requireTeamAccess(String authorization) {
        AuthRole role = tokenService.validateAuthorization(authorization);
        if (role != AuthRole.TEAM && role != AuthRole.ADMIN) {
            throw new UnauthorizedException("Acesso restrito à equipe.");
        }
    }

    public void requireAdminAccess(String authorization) {
        if (tokenService.validateAuthorization(authorization) != AuthRole.ADMIN) {
            throw new UnauthorizedException("Acesso restrito à coordenação.");
        }
    }

    private boolean isTeamPin(String pin) {
        return secureEquals(pin, teamPin);
    }

    private boolean isAdminPin(String pin) {
        return secureEquals(pin, adminPin);
    }

    private boolean secureEquals(String provided, String expected) {
        if (provided == null) {
            return false;
        }
        return MessageDigest.isEqual(
                provided.getBytes(StandardCharsets.UTF_8),
                expected.getBytes(StandardCharsets.UTF_8));
    }
}
