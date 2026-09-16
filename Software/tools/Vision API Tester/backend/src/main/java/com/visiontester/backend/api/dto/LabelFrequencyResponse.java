package com.visiontester.backend.api.dto;

public record LabelFrequencyResponse(
        String label,
        long count,
        double averageConfidence
) {
}
