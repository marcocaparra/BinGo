package com.visiontester.backend.api.dto;

import com.visiontester.backend.domain.ImageValidationStatus;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.UUID;

public record SaveImageValidationRequest(
        @NotNull ImageValidationStatus imageValidationStatus,
        Boolean humanIsEwaste,
        UUID humanConfirmedClassId,
        @Size(max = 2000) String humanNote
) {
}
