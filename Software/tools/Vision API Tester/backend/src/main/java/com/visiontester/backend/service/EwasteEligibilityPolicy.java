package com.visiontester.backend.service;

import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationCategoryType;
import com.visiontester.backend.domain.ClassificationStatus;
import com.visiontester.backend.domain.EwasteEligibility;
import java.util.List;
import org.springframework.stereotype.Component;

@Component
public class EwasteEligibilityPolicy {

    public EwasteEligibility derive(ClassificationDecision decision) {
        return derive(
                decision.status(),
                decision.suggestedClass(),
                decision.relevantCandidates(),
                decision.eligibilityCandidates()
        );
    }

    public EwasteEligibility derive(
            ClassificationStatus status,
            ClassificationCategory category,
            List<ClassificationCandidate> relevantCandidates,
            List<ClassificationCandidate> eligibilityCandidates
    ) {
        if (status == ClassificationStatus.NO_MATCH) {
            return EwasteEligibility.REVIEW;
        }

        if (status == ClassificationStatus.CLASSIFIED) {
            EwasteEligibility primaryEligibility = eligibilityFor(category);
            if (primaryEligibility != EwasteEligibility.REVIEW) {
                return primaryEligibility;
            }

            boolean hasEligibleGenericEvidence = eligibilityCandidates.stream()
                    .filter(candidate -> candidate.category().getCategoryType() == ClassificationCategoryType.GENERIC)
                    .anyMatch(candidate -> eligibilityFor(candidate.category()) == EwasteEligibility.ELIGIBLE);
            return hasEligibleGenericEvidence ? EwasteEligibility.ELIGIBLE : EwasteEligibility.REVIEW;
        }

        if (eligibilityCandidates.isEmpty()) {
            return EwasteEligibility.REVIEW;
        }

        boolean allEligible = eligibilityCandidates.stream()
                .allMatch(candidate -> eligibilityFor(candidate.category()) == EwasteEligibility.ELIGIBLE);
        if (allEligible) {
            return EwasteEligibility.ELIGIBLE;
        }

        boolean allInvalid = eligibilityCandidates.stream()
                .allMatch(candidate -> eligibilityFor(candidate.category()) == EwasteEligibility.NOT_ELIGIBLE);
        if (allInvalid) {
            return EwasteEligibility.NOT_ELIGIBLE;
        }

        return EwasteEligibility.REVIEW;
    }

    private EwasteEligibility eligibilityFor(ClassificationCategory category) {
        if (category == null) {
            return EwasteEligibility.REVIEW;
        }
        return category.getDefaultEwasteEligibility();
    }
}
