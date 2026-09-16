package com.visiontester.backend.api.dto;

public record ProviderSummaryResponse(
        String provider,
        long runs,
        double averageResponseTimeMs
) {
}
