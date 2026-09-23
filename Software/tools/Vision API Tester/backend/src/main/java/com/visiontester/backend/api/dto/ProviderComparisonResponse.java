package com.visiontester.backend.api.dto;

public record ProviderComparisonResponse(
        String provider,
        long runs,
        long evaluatedRuns,
        long eligibilityEvaluatedRuns,
        long eligibilityCorrectRuns,
        long eligibilityIncorrectRuns,
        long reviewRuns,
        long classificationEvaluatedRuns,
        long classificationCorrectRuns,
        double eligibilityAccuracyRate,
        double classificationAccuracyRate,
        double macroClassificationAccuracyRate,
        double reviewRate,
        double sampleCoverageRate,
        double averageResponseTimeMs,
        double medianResponseTimeMs,
        double p95ResponseTimeMs,
        double minResponseTimeMs,
        double maxResponseTimeMs
) {
}
