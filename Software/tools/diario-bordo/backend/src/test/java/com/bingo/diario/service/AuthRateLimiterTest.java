package com.bingo.diario.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;

import org.junit.jupiter.api.Test;

import com.bingo.diario.exception.TooManyRequestsException;

class AuthRateLimiterTest {

    @Test
    void blocksAfterTenFailuresAndReleasesAfterFifteenMinutes() {
        MutableClock clock = new MutableClock(Instant.parse("2026-07-14T12:00:00Z"));
        AuthRateLimiter limiter = new AuthRateLimiter(clock);

        for (int attempt = 0; attempt < 10; attempt += 1) {
            limiter.requireAllowed("client:TEAM");
            limiter.recordFailure("client:TEAM");
        }

        assertThatThrownBy(() -> limiter.requireAllowed("client:TEAM"))
                .isInstanceOf(TooManyRequestsException.class);

        clock.advance(Duration.ofMinutes(16));

        assertThatCode(() -> limiter.requireAllowed("client:TEAM")).doesNotThrowAnyException();
    }

    private static final class MutableClock extends Clock {
        private Instant instant;

        private MutableClock(Instant instant) {
            this.instant = instant;
        }

        void advance(Duration duration) {
            instant = instant.plus(duration);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return instant;
        }
    }
}
