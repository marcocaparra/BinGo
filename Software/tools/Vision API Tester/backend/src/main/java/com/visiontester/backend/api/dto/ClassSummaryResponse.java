package com.visiontester.backend.api.dto;

public record ClassSummaryResponse(
        String expectedClass,
        long evaluations,
        long correctEvaluations,
        double accuracyRate
) {
}
