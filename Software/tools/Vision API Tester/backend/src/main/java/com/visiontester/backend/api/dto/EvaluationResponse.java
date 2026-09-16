package com.visiontester.backend.api.dto;

import com.visiontester.backend.domain.EvaluationResult;
import java.time.OffsetDateTime;
import java.util.UUID;

public record EvaluationResponse(
        UUID id,
        UUID providerRunId,
        UUID correctClassId,
        String correctClass,
        String correctClassName,
        EvaluationResult evaluationResult,
        boolean targetObject,
        String humanNote,
        OffsetDateTime evaluatedAt
) {
}
