package com.visiontester.backend.api.dto;

import java.util.List;
import java.util.UUID;

public record DashboardMetricsResponse(
        UUID projectId,
        long totalImages,
        long totalProviderRuns,
        long completedEvaluations,
        long pendingEvaluations,
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
        double specificClassificationRate,
        double averageResponseTimeMs,
        List<ProviderSummaryResponse> providers,
        List<ClassSummaryResponse> classes,
        DashboardSampleQualityResponse sampleQuality,
        List<ProviderDecisionMetricsResponse> decisionMetrics,
        List<ProviderComparisonResponse> providerComparisons,
        List<ClassProviderPerformanceResponse> classPerformance,
        List<ClassErrorSummaryResponse> classErrors,
        List<DashboardAlertResponse> alerts
) {
}
