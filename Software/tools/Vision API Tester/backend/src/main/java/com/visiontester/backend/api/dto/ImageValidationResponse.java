package com.visiontester.backend.api.dto;

import com.visiontester.backend.domain.ImageValidationStatus;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public record ImageValidationResponse(
        UUID id,
        UUID imageId,
        ImageValidationStatus imageValidationStatus,
        Boolean humanIsEwaste,
        ClassificationCategoryResponse humanConfirmedClass,
        String humanNote,
        OffsetDateTime validatedAt,
        List<ProviderValidationResultResponse> providerResults
) {
}
