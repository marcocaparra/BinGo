package com.bingo.diario.config;

import java.time.Clock;
import java.time.ZoneId;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class TimeConfig {

    public static final ZoneId DIARY_ZONE = ZoneId.of("America/Sao_Paulo");

    @Bean
    Clock diaryClock() {
        return Clock.system(DIARY_ZONE);
    }
}
