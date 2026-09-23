package com.visiontester.backend.api.dto;

import com.visiontester.backend.domain.ClassificationCategoryType;
import com.visiontester.backend.domain.EwasteEligibility;
import java.util.UUID;
import java.util.List;

public record ClassificationCategoryResponse(
        UUID id,
        String code,
        String name,
        List<String> aliases,
        ClassificationCategoryType categoryType,
        EwasteEligibility defaultEwasteEligibility,
        int displayOrder,
        boolean active
) {
}
