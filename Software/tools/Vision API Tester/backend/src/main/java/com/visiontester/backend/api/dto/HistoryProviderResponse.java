package com.visiontester.backend.api.dto;

import com.visiontester.backend.domain.EwasteEligibility;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import tools.jackson.databind.JsonNode;

public record HistoryProviderResponse(
        UUID providerRunId,
        String provider,
        String status,
        Integer responseTimeMs,
        List<ProviderLabelResponse> labels,
        ClassificationCategoryResponse suggestedClass,
        String classificationStatus,
        BigDecimal classificationScore,
        BigDecimal classificationMargin,
        String classificationEngineVersion,
        JsonNode classificationEvidence,
        EwasteEligibility ewasteEligibility,
        Boolean eligibilityCorrect,
        Boolean classificationCorrect,
        JsonNode rawResponse,
        EvaluationResponse evaluation,
        OffsetDateTime createdAt
) {
}
