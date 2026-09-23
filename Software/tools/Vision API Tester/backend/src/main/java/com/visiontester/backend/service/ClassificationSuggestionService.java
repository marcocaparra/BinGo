package com.visiontester.backend.service;

import com.visiontester.backend.domain.ClassificationAlias;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationCategoryType;
import com.visiontester.backend.domain.ClassificationStatus;
import com.visiontester.backend.domain.ProviderLabel;
import com.visiontester.backend.repository.ClassificationCategoryRepository;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.Normalizer;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.stereotype.Service;

@Service
public class ClassificationSuggestionService {

    static final String ENGINE_VERSION = "ewaste-rules-v3";
    static final BigDecimal MINIMUM_SCORE = new BigDecimal("50.000");
    static final BigDecimal MINIMUM_MARGIN = new BigDecimal("5.000");
    private static final BigDecimal ADDITIONAL_EVIDENCE_WEIGHT = new BigDecimal("0.20");
    private static final BigDecimal HUNDRED = new BigDecimal("100.000");

    private final ClassificationCategoryRepository repository;

    public ClassificationSuggestionService(ClassificationCategoryRepository repository) {
        this.repository = repository;
    }

    ClassificationDecision classify(List<ProviderLabel> labels) {
        List<ClassificationCategory> categories = repository.findByActiveTrueOrderByDisplayOrderAscNameAsc();
        return classify(labels, categories);
    }

    ClassificationDecision classify(List<ProviderLabel> labels, List<ClassificationCategory> categories) {
        List<ClassificationCandidate> ranking = categories.stream()
                .filter(ClassificationCategory::isActive)
                .map(category -> score(category, labels))
                .filter(candidate -> !candidate.evidence().isEmpty())
                .sorted(Comparator.comparing(ClassificationCandidate::score).reversed()
                        .thenComparing(candidate -> candidate.category().getDisplayOrder())
                        .thenComparing(candidate -> candidate.category().getCode()))
                .toList();

        if (ranking.isEmpty()) {
            return new ClassificationDecision(
                    null,
                    ClassificationStatus.NO_MATCH,
                    BigDecimal.ZERO.setScale(3),
                    BigDecimal.ZERO.setScale(3),
                    ENGINE_VERSION,
                    List.of(),
                    List.of(),
                    List.of()
            );
        }

        List<ClassificationCandidate> classifiableRanking = ranking.stream()
                .filter(candidate -> candidate.category().getCategoryType() != ClassificationCategoryType.GENERIC)
                .toList();
        if (classifiableRanking.isEmpty()) {
            ClassificationCandidate strongestGeneric = ranking.getFirst();
            return new ClassificationDecision(
                    null,
                    ClassificationStatus.BELOW_THRESHOLD,
                    strongestGeneric.score(),
                    strongestGeneric.score(),
                    ENGINE_VERSION,
                    strongestGeneric.evidence(),
                    List.of(),
                    ranking.stream()
                            .filter(candidate -> candidate.score().compareTo(MINIMUM_SCORE) >= 0)
                            .toList()
            );
        }

        ClassificationCandidate winner = classifiableRanking.getFirst();
        BigDecimal margin = classifiableRanking.size() == 1
                ? winner.score()
                : winner.score().subtract(classifiableRanking.get(1).score())
                        .max(BigDecimal.ZERO)
                        .setScale(3, RoundingMode.HALF_UP);
        List<ClassificationCandidate> relevantCandidates = classifiableRanking.stream()
                .filter(candidate -> candidate.score().compareTo(MINIMUM_SCORE) >= 0)
                .filter(candidate -> winner.score().subtract(candidate.score()).compareTo(MINIMUM_MARGIN) <= 0)
                .toList();
        List<ClassificationCandidate> eligibilityCandidates = java.util.stream.Stream.concat(
                        relevantCandidates.stream(),
                        ranking.stream()
                                .filter(candidate -> candidate.category().getCategoryType() == ClassificationCategoryType.GENERIC)
                                .filter(candidate -> candidate.score().compareTo(MINIMUM_SCORE) >= 0)
                )
                .distinct()
                .toList();

        ClassificationStatus status;
        ClassificationCategory suggestedClass = null;
        if (winner.score().compareTo(MINIMUM_SCORE) < 0) {
            status = ClassificationStatus.BELOW_THRESHOLD;
        } else if (relevantCandidates.size() > 1) {
            status = ClassificationStatus.AMBIGUOUS;
            suggestedClass = winner.category();
        } else {
            status = ClassificationStatus.CLASSIFIED;
            suggestedClass = winner.category();
        }

        return new ClassificationDecision(
                suggestedClass,
                status,
                winner.score(),
                margin,
                ENGINE_VERSION,
                winner.evidence(),
                relevantCandidates,
                eligibilityCandidates
        );
    }

    private ClassificationCandidate score(ClassificationCategory category, List<ProviderLabel> labels) {
        Set<String> terms = new LinkedHashSet<>();
        terms.add(normalize(category.getCode()));
        terms.add(normalize(category.getName()));
        category.getAliases().stream()
                .map(ClassificationAlias::getAlias)
                .map(this::normalize)
                .filter(term -> !term.isBlank())
                .forEach(terms::add);

        List<ClassificationEvidence> evidence = labels.stream()
                .map(label -> strongestMatch(label, terms))
                .filter(match -> match != null)
                .sorted(Comparator.comparing(ClassificationEvidence::contribution).reversed()
                        .thenComparing(ClassificationEvidence::label))
                .toList();

        if (evidence.isEmpty()) {
            return new ClassificationCandidate(category, BigDecimal.ZERO.setScale(3), List.of());
        }

        BigDecimal score = evidence.getFirst().contribution();
        for (ClassificationEvidence additionalEvidence : evidence.subList(1, evidence.size())) {
            BigDecimal remainingScore = HUNDRED.subtract(score);
            BigDecimal contributionRatio = additionalEvidence.contribution().movePointLeft(2);
            BigDecimal increment = remainingScore
                    .multiply(contributionRatio)
                    .multiply(ADDITIONAL_EVIDENCE_WEIGHT);
            score = score.add(increment);
        }

        return new ClassificationCandidate(
                category,
                score.min(HUNDRED).setScale(3, RoundingMode.HALF_UP),
                evidence
        );
    }

    private ClassificationEvidence strongestMatch(ProviderLabel label, Set<String> terms) {
        String normalizedLabel = normalize(label.getLabelName());
        if (normalizedLabel.isBlank()) {
            return null;
        }

        TermMatch match = terms.stream()
                .map(term -> match(normalizedLabel, term))
                .filter(candidate -> candidate != null)
                .sorted(Comparator.comparing(TermMatch::weight).reversed()
                        .thenComparing(matchCandidate -> matchCandidate.term().length(), Comparator.reverseOrder()))
                .findFirst()
                .orElse(null);
        if (match == null) {
            return null;
        }

        BigDecimal confidence = label.getConfidence()
                .max(BigDecimal.ZERO)
                .min(new BigDecimal("100.000"));
        BigDecimal contribution = confidence.multiply(match.weight()).setScale(3, RoundingMode.HALF_UP);
        return new ClassificationEvidence(
                label.getLabelName(),
                label.getConfidence(),
                match.term(),
                match.type(),
                contribution
        );
    }

    private TermMatch match(String normalizedLabel, String term) {
        if (term.isBlank()) {
            return null;
        }
        if (normalizedLabel.equals(term)) {
            return new TermMatch(term, "EXACT", BigDecimal.ONE);
        }

        String paddedLabel = " " + normalizedLabel + " ";
        String paddedTerm = " " + term + " ";
        if (paddedLabel.contains(paddedTerm)) {
            BigDecimal weight = term.contains(" ") ? new BigDecimal("0.92") : new BigDecimal("0.80");
            return new TermMatch(term, "PHRASE", weight);
        }
        return null;
    }

    private String normalize(String value) {
        return Normalizer.normalize(value == null ? "" : value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", " ")
                .trim()
                .replaceAll("\\s+", " ");
    }

    private record TermMatch(String term, String type, BigDecimal weight) {
    }

}
