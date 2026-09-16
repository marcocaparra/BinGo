package com.visiontester.backend.api.dto;

import java.util.List;

public record ClassErrorSummaryResponse(
        String expectedClass,
        String provider,
        long wrongClassRuns,
        long unclassifiedRuns,
        long totalIncorrectRuns,
        List<LabelFrequencyResponse> topReturnedLabels
) {
}
