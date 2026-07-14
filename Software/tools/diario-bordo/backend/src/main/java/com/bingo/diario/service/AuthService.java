package com.bingo.diario.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.bingo.diario.dto.AuthRole;
import com.bingo.diario.exception.UnauthorizedException;

@Service
public class AuthService {

    public static final String PASSWORD_HEADER = "X-Diary-Password";

    private final String teamPin;
    private final String adminPin;

    public AuthService(
            @Value("${app.auth.team-pin}") String teamPin,
            @Value("${app.auth.admin-pin}") String adminPin) {
        this.teamPin = teamPin;
        this.adminPin = adminPin;
    }

    public AuthRole validateAccess(AuthRole requestedRole, String pin) {
        if (requestedRole == AuthRole.ADMIN && isAdminPin(pin)) {
            return AuthRole.ADMIN;
        }
        if (requestedRole == AuthRole.TEAM && isTeamPin(pin)) {
            return AuthRole.TEAM;
        }
        throw new UnauthorizedException("PIN inválido.");
    }

    public void requireTeamAccess(String pin) {
        if (!isTeamPin(pin) && !isAdminPin(pin)) {
            throw new UnauthorizedException("PIN inválido.");
        }
    }

    public void requireAdminAccess(String pin) {
        if (!isAdminPin(pin)) {
            throw new UnauthorizedException("Acesso restrito à coordenação.");
        }
    }

    private boolean isTeamPin(String pin) {
        return pin != null && pin.equals(teamPin);
    }

    private boolean isAdminPin(String pin) {
        return pin != null && pin.equals(adminPin);
    }
}
