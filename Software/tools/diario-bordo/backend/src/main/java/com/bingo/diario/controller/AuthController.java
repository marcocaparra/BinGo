package com.bingo.diario.controller;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.bingo.diario.dto.AuthRequest;
import com.bingo.diario.dto.AuthResponse;
import com.bingo.diario.service.AuthService;

import jakarta.validation.Valid;
import jakarta.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/access")
    public AuthResponse access(
            @Valid @RequestBody AuthRequest request,
            HttpServletRequest httpRequest) {
        return authService.authenticate(request.role(), request.pin(), httpRequest.getRemoteAddr());
    }
}
