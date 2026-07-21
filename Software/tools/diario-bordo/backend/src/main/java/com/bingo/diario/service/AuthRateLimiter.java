package com.bingo.diario.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.stereotype.Service;

import com.bingo.diario.exception.TooManyRequestsException;

@Service
public class AuthRateLimiter {

    private static final int MAX_FAILURES = 10;
    private static final Duration WINDOW = Duration.ofMinutes(15);
    private static final Duration BLOCK_DURATION = Duration.ofMinutes(15);

    private final ConcurrentHashMap<String, AttemptWindow> attempts = new ConcurrentHashMap<>();
    private final Clock clock;

    public AuthRateLimiter(Clock clock) {
        this.clock = clock;
    }

    public void requireAllowed(String key) {
        AttemptWindow window = attempts.get(key);
        if (window != null && window.blockedUntil() != null
                && window.blockedUntil().isAfter(Instant.now(clock))) {
            throw new TooManyRequestsException("Muitas tentativas de acesso. Aguarde 15 minutos.");
        }
    }

    public void recordFailure(String key) {
        Instant now = Instant.now(clock);
        attempts.compute(key, (ignored, current) -> {
            int failures = current == null || current.startedAt().plus(WINDOW).isBefore(now)
                    ? 1
                    : current.failures() + 1;
            Instant startedAt = failures == 1 ? now : current.startedAt();
            Instant blockedUntil = failures >= MAX_FAILURES ? now.plus(BLOCK_DURATION) : null;
            return new AttemptWindow(failures, startedAt, blockedUntil);
        });
    }

    public void clear(String key) {
        attempts.remove(key);
    }

    private record AttemptWindow(int failures, Instant startedAt, Instant blockedUntil) {
    }
}
