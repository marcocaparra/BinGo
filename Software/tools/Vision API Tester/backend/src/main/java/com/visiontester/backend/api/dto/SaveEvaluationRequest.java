package com.visiontester.backend.api.dto;

import com.visiontester.backend.domain.EvaluationResult;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.UUID;

public record SaveEvaluationRequest(
        @NotNull UUID correctClassId,
        @NotNull EvaluationResult evaluationResult,
        boolean targetObject,
        @Size(max = 2000) String humanNote
) {
}
