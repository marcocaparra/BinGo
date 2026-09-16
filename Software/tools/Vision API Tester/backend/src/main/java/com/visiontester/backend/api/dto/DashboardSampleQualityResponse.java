package com.visiontester.backend.api.dto;

import java.util.List;

public record DashboardSampleQualityResponse(
        long validImageValidations,
        long invalidImageValidations,
        long evaluatedRuns,
        long pendingRuns,
        long legacyFallbackRuns,
        long ewasteTruthRuns,
        long nonEwasteTruthRuns,
        long reviewRuns,
        long classificationEvaluatedRuns,
        double evaluationCoverageRate,
        int minimumRecommendedEvaluationsPerProvider,
        int minimumRecommendedEvaluationsPerClass,
        List<String> providersWithLowSample,
        List<String> classesWithLowSample
) {
}
