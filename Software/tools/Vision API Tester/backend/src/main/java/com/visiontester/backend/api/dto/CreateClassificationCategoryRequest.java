package com.visiontester.backend.api.dto;

import com.visiontester.backend.domain.ClassificationCategoryType;
import com.visiontester.backend.domain.EwasteEligibility;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;

public record CreateClassificationCategoryRequest(
        @Size(max = 80) String code,
        @NotBlank @Size(max = 160) String name,
        @Size(max = 30) List<@NotBlank @Size(max = 180) String> aliases,
        ClassificationCategoryType categoryType,
        EwasteEligibility defaultEwasteEligibility
) {
}
