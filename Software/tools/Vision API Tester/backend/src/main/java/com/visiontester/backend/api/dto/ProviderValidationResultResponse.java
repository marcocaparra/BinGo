package com.visiontester.backend.api.dto;

import java.util.UUID;

public record ProviderValidationResultResponse(
        UUID providerRunId,
        String provider,
        Boolean eligibilityCorrect,
        Boolean classificationCorrect
) {
}
