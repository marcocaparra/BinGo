package com.visiontester.backend.service;

import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationStatus;
import java.math.BigDecimal;
import java.util.List;

record ClassificationDecision(
        ClassificationCategory suggestedClass,
        ClassificationStatus status,
        BigDecimal score,
        BigDecimal margin,
        String engineVersion,
        List<ClassificationEvidence> evidence,
        List<ClassificationCandidate> relevantCandidates,
        List<ClassificationCandidate> eligibilityCandidates
) {
}
