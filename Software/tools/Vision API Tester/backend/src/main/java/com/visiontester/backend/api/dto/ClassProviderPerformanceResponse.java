package com.visiontester.backend.api.dto;

public record ClassProviderPerformanceResponse(
        String expectedClass,
        String provider,
        long evaluatedRuns,
        long correctRuns,
        long wrongClassRuns,
        long unclassifiedRuns,
        double classificationAccuracyRate,
        double specificClassificationRate,
        double averageResponseTimeMs
) {
}
