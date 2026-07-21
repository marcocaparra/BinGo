package com.bingo.diario.controller;

import java.time.Clock;
import java.time.Instant;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.bingo.diario.dto.HealthResponse;

@RestController
public class HealthController {

    private final Clock clock;

    public HealthController(Clock clock) {
        this.clock = clock;
    }

    @GetMapping("/health")
    public HealthResponse health() {
        return new HealthResponse("UP", "diario-bordo-api", Instant.now(clock));
    }
}
