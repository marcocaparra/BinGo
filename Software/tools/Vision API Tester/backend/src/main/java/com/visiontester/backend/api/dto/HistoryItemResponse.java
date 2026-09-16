package com.visiontester.backend.api.dto;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public record HistoryItemResponse(
        UUID imageId,
        String imageName,
        OffsetDateTime uploadedAt,
        UUID projectId,
        String projectName,
        ImageValidationResponse imageValidation,
        List<HistoryProviderResponse> providerResults
) {
}
