package com.visiontester.backend.api.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;
import tools.jackson.databind.JsonNode;

public record SaveProviderResultRequest(
        @NotNull UUID imageId,
        @NotBlank @Size(max = 80) String provider,
        @PositiveOrZero Integer responseTimeMs,
        @Valid @Size(max = 100) List<ProviderLabelRequest> labels,
        JsonNode rawResponse
) {
}
