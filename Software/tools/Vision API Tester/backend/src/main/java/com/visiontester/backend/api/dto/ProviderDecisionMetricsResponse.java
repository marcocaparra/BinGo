package com.visiontester.backend.api.dto;

public record ProviderDecisionMetricsResponse(
        String provider,
        long totalRuns,
        long validatedRuns,
        long eligibilityEvaluatedRuns,
        long eligibilityCorrectRuns,
        double eligibilityAccuracyRate,
        double precisionRate,
        double recallRate,
        long falsePositives,
        long falseNegatives,
        long reviewRuns,
        double reviewRate,
        long classificationEvaluatedRuns,
        long classificationCorrectRuns,
        double classificationAccuracyRate,
        long specificallyClassifiedRuns,
        double specificClassificationRate
) {
}
