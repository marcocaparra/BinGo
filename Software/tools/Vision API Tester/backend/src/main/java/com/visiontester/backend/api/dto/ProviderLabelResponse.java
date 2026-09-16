package com.visiontester.backend.api.dto;

import java.math.BigDecimal;
import java.util.UUID;

public record ProviderLabelResponse(
        UUID id,
        String name,
        BigDecimal confidence
) {
}
