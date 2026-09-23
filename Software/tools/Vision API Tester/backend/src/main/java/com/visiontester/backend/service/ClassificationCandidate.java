package com.visiontester.backend.service;

import com.visiontester.backend.domain.ClassificationCategory;
import java.math.BigDecimal;
import java.util.List;

record ClassificationCandidate(
        ClassificationCategory category,
        BigDecimal score,
        List<ClassificationEvidence> evidence
) {
}
