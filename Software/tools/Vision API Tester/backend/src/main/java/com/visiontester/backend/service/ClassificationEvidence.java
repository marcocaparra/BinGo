package com.visiontester.backend.service;

import java.math.BigDecimal;

public record ClassificationEvidence(
        String label,
        BigDecimal labelConfidence,
        String matchedTerm,
        String matchType,
        BigDecimal contribution
) {
}
