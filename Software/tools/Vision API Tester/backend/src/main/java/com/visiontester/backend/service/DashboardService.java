package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.ClassErrorSummaryResponse;
import com.visiontester.backend.api.dto.ClassProviderPerformanceResponse;
import com.visiontester.backend.api.dto.ClassSummaryResponse;
import com.visiontester.backend.api.dto.DashboardAlertResponse;
import com.visiontester.backend.api.dto.DashboardMetricsResponse;
import com.visiontester.backend.api.dto.DashboardSampleQualityResponse;
import com.visiontester.backend.api.dto.LabelFrequencyResponse;
import com.visiontester.backend.api.dto.ProviderComparisonResponse;
import com.visiontester.backend.api.dto.ProviderDecisionMetricsResponse;
import com.visiontester.backend.api.dto.ProviderSummaryResponse;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationCategoryType;
import com.visiontester.backend.domain.ClassificationStatus;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.domain.HumanEvaluation;
import com.visiontester.backend.domain.ImageValidation;
import com.visiontester.backend.domain.ImageValidationStatus;
import com.visiontester.backend.domain.ProviderLabel;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.repository.HumanEvaluationRepository;
import com.visiontester.backend.repository.ImageAssetRepository;
import com.visiontester.backend.repository.ImageValidationRepository;
import com.visiontester.backend.repository.ProviderRunRepository;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.function.ToLongFunction;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DashboardService {

    private static final int MIN_EVALUATIONS_PER_PROVIDER = 5;
    private static final int MIN_EVALUATIONS_PER_CLASS = 3;

    private final ImageAssetRepository imageAssetRepository;
    private final ProviderRunRepository providerRunRepository;
    private final HumanEvaluationRepository humanEvaluationRepository;
    private final ImageValidationRepository imageValidationRepository;

    public DashboardService(
            ImageAssetRepository imageAssetRepository,
            ProviderRunRepository providerRunRepository,
            HumanEvaluationRepository humanEvaluationRepository,
            ImageValidationRepository imageValidationRepository
    ) {
        this.imageAssetRepository = imageAssetRepository;
        this.providerRunRepository = providerRunRepository;
        this.humanEvaluationRepository = humanEvaluationRepository;
        this.imageValidationRepository = imageValidationRepository;
    }

    @Transactional(readOnly = true)
    public DashboardMetricsResponse metrics(UUID projectId) {
        long totalImages = projectId == null
                ? imageAssetRepository.count()
                : imageAssetRepository.countByProject_Id(projectId);
        List<ProviderRun> providerRuns = projectId == null
                ? providerRunRepository.findAllForDashboard()
                : providerRunRepository.findAllForDashboardByProjectId(projectId);
        List<HumanEvaluation> legacyEvaluations = projectId == null
                ? humanEvaluationRepository.findAllForDashboard()
                : humanEvaluationRepository.findAllForDashboardByProjectId(projectId);
        List<ImageValidation> imageValidations = projectId == null
                ? imageValidationRepository.findAllForDashboard()
                : imageValidationRepository.findAllForDashboardByProjectId(projectId);

        DashboardContext context = buildContext(providerRuns, legacyEvaluations, imageValidations);
        long totalRuns = providerRuns.size();
        long completedEvaluations = sum(context, stats -> stats.evaluatedRuns);
        long pendingEvaluations = Math.max(totalRuns - completedEvaluations, 0);
        long eligibilityEvaluatedRuns = sum(context, stats -> stats.eligibilityEvaluatedRuns);
        long eligibilityCorrectRuns = sum(context, stats -> stats.eligibilityCorrectRuns);
        long truePositives = sum(context, stats -> stats.truePositives);
        long falsePositives = sum(context, stats -> stats.falsePositives);
        long falseNegatives = sum(context, stats -> stats.falseNegatives);
        long reviewRuns = sum(context, stats -> stats.reviewRuns);
        long classificationEvaluatedRuns = sum(context, stats -> stats.classificationEvaluatedRuns);
        long classificationCorrectRuns = sum(context, stats -> stats.classificationCorrectRuns);
        long specificallyClassifiedRuns = sum(context, stats -> stats.specificallyClassifiedRuns);

        return new DashboardMetricsResponse(
                projectId,
                totalImages,
                totalRuns,
                completedEvaluations,
                pendingEvaluations,
                eligibilityEvaluatedRuns,
                eligibilityCorrectRuns,
                percentage(eligibilityCorrectRuns, eligibilityEvaluatedRuns),
                percentage(truePositives, truePositives + falsePositives),
                percentage(truePositives, truePositives + falseNegatives),
                falsePositives,
                falseNegatives,
                reviewRuns,
                percentage(reviewRuns, totalRuns),
                classificationEvaluatedRuns,
                classificationCorrectRuns,
                percentage(classificationCorrectRuns, classificationEvaluatedRuns),
                specificallyClassifiedRuns,
                percentage(specificallyClassifiedRuns, classificationEvaluatedRuns),
                average(providerRuns.stream()
                        .map(ProviderRun::getResponseTimeMs)
                        .filter(Objects::nonNull)
                        .map(Integer::doubleValue)
                        .toList()),
                providerSummaries(context),
                classSummaries(context),
                sampleQuality(totalRuns, completedEvaluations, pendingEvaluations, context),
                decisionMetrics(context),
                providerComparisons(context),
                classPerformance(context),
                classErrors(context),
                alerts(totalImages, totalRuns, completedEvaluations, pendingEvaluations, context)
        );
    }

    private DashboardContext buildContext(
            List<ProviderRun> providerRuns,
            List<HumanEvaluation> legacyEvaluations,
            List<ImageValidation> imageValidations
    ) {
        DashboardContext context = new DashboardContext();
        Map<UUID, ImageValidation> validationByImageId = imageValidations.stream()
                .collect(Collectors.toMap(validation -> validation.getImage().getId(), validation -> validation));
        Map<UUID, HumanEvaluation> legacyEvaluationByRunId = legacyEvaluations.stream()
                .collect(Collectors.toMap(evaluation -> evaluation.getProviderRun().getId(), evaluation -> evaluation));

        context.validImageValidations = imageValidations.stream()
                .filter(validation -> validation.getValidationStatus() == ImageValidationStatus.VALID)
                .count();
        context.invalidImageValidations = imageValidations.size() - context.validImageValidations;

        for (ProviderRun providerRun : providerRuns) {
            ProviderStats providerStats = context.providerStats.computeIfAbsent(
                    providerRun.getProvider(),
                    ProviderStats::new
            );
            providerStats.runs++;
            providerStats.recordLatency(providerRun);

            if (providerRun.getEwasteEligibility() == EwasteEligibility.REVIEW) {
                providerStats.reviewRuns++;
            }

            ImageValidation validation = validationByImageId.get(providerRun.getImage().getId());
            RunAssessment assessment = validation == null
                    ? fromLegacy(providerRun, legacyEvaluationByRunId.get(providerRun.getId()))
                    : fromImageValidation(providerRun, validation);

            if (!assessment.evaluated()) {
                continue;
            }

            if (assessment.legacyFallback()) {
                context.legacyFallbackRuns++;
            }
            if (assessment.humanIsEwaste()) {
                context.ewasteTruthRuns++;
            } else {
                context.nonEwasteTruthRuns++;
            }

            providerStats.record(assessment);
            if (assessment.humanClass() != null) {
                String expectedClass = assessment.humanClass().getCode();
                providerStats.classStats
                        .computeIfAbsent(expectedClass, ClassStats::new)
                        .record(assessment);
                context.classStats
                        .computeIfAbsent(expectedClass, ClassStats::new)
                        .record(assessment);

                if (!Boolean.TRUE.equals(assessment.classificationCorrect())) {
                    context.errorStats
                            .computeIfAbsent(expectedClass, ignored -> new LinkedHashMap<>())
                            .computeIfAbsent(
                                    providerRun.getProvider(),
                                    provider -> new ErrorStats(expectedClass, provider)
                            )
                            .record(assessment);
                }
            }
        }

        return context;
    }

    private RunAssessment fromImageValidation(ProviderRun providerRun, ImageValidation validation) {
        if (validation.getValidationStatus() != ImageValidationStatus.VALID) {
            return RunAssessment.pending(providerRun);
        }

        return assessed(
                providerRun,
                Boolean.TRUE.equals(validation.getHumanIsEwaste()),
                validation.getHumanConfirmedClass(),
                false
        );
    }

    private RunAssessment fromLegacy(ProviderRun providerRun, HumanEvaluation evaluation) {
        if (evaluation == null) {
            return RunAssessment.pending(providerRun);
        }

        return assessed(
                providerRun,
                evaluation.isTargetObject(),
                evaluation.isTargetObject() ? evaluation.getCorrectClass() : null,
                true
        );
    }

    private RunAssessment assessed(
            ProviderRun providerRun,
            boolean humanIsEwaste,
            ClassificationCategory humanClass,
            boolean legacyFallback
    ) {
        Boolean eligibilityCorrect = providerRun.getEwasteEligibility() == EwasteEligibility.REVIEW
                ? null
                : providerRun.getEligibilityCorrect();
        if (eligibilityCorrect == null && providerRun.getEwasteEligibility() != EwasteEligibility.REVIEW) {
            eligibilityCorrect = providerRun.getEwasteEligibility() == EwasteEligibility.ELIGIBLE
                    ? humanIsEwaste
                    : !humanIsEwaste;
        }

        Boolean classificationCorrect = humanClass == null ? null : providerRun.getClassificationCorrect();
        if (classificationCorrect == null && humanClass != null) {
            classificationCorrect = providerRun.getSuggestedClass() != null
                    && providerRun.getSuggestedClass().getId().equals(humanClass.getId());
        }

        return new RunAssessment(
                providerRun,
                true,
                legacyFallback,
                humanIsEwaste,
                humanClass,
                eligibilityCorrect,
                classificationCorrect,
                isSpecificClassification(providerRun)
        );
    }

    private boolean isSpecificClassification(ProviderRun providerRun) {
        return providerRun.getClassificationStatus() == ClassificationStatus.CLASSIFIED
                && providerRun.getSuggestedClass() != null
                && providerRun.getSuggestedClass().getCategoryType() == ClassificationCategoryType.SPECIFIC;
    }

    private List<ProviderDecisionMetricsResponse> decisionMetrics(DashboardContext context) {
        return context.providerStats.values().stream()
                .sorted(Comparator.comparing(stats -> stats.provider))
                .map(stats -> new ProviderDecisionMetricsResponse(
                        stats.provider,
                        stats.runs,
                        stats.evaluatedRuns,
                        stats.eligibilityEvaluatedRuns,
                        stats.eligibilityCorrectRuns,
                        percentage(stats.eligibilityCorrectRuns, stats.eligibilityEvaluatedRuns),
                        percentage(stats.truePositives, stats.truePositives + stats.falsePositives),
                        percentage(stats.truePositives, stats.truePositives + stats.falseNegatives),
                        stats.falsePositives,
                        stats.falseNegatives,
                        stats.reviewRuns,
                        percentage(stats.reviewRuns, stats.runs),
                        stats.classificationEvaluatedRuns,
                        stats.classificationCorrectRuns,
                        percentage(stats.classificationCorrectRuns, stats.classificationEvaluatedRuns),
                        stats.specificallyClassifiedRuns,
                        percentage(stats.specificallyClassifiedRuns, stats.classificationEvaluatedRuns)
                ))
                .toList();
    }

    private List<ProviderComparisonResponse> providerComparisons(DashboardContext context) {
        return context.providerStats.values().stream()
                .sorted(providerRanking())
                .map(stats -> {
                    List<Double> sortedTimes = stats.responseTimes.stream().sorted().toList();
                    return new ProviderComparisonResponse(
                            stats.provider,
                            stats.runs,
                            stats.evaluatedRuns,
                            stats.eligibilityEvaluatedRuns,
                            stats.eligibilityCorrectRuns,
                            stats.eligibilityEvaluatedRuns - stats.eligibilityCorrectRuns,
                            stats.reviewRuns,
                            stats.classificationEvaluatedRuns,
                            stats.classificationCorrectRuns,
                            percentage(stats.eligibilityCorrectRuns, stats.eligibilityEvaluatedRuns),
                            percentage(stats.classificationCorrectRuns, stats.classificationEvaluatedRuns),
                            macroClassificationAccuracy(stats),
                            percentage(stats.reviewRuns, stats.runs),
                            percentage(stats.evaluatedRuns, stats.runs),
                            average(sortedTimes),
                            percentile(sortedTimes, 50),
                            percentile(sortedTimes, 95),
                            sortedTimes.isEmpty() ? 0.0 : round(sortedTimes.getFirst()),
                            sortedTimes.isEmpty() ? 0.0 : round(sortedTimes.getLast())
                    );
                })
                .toList();
    }

    private Comparator<ProviderStats> providerRanking() {
        return Comparator
                .comparingDouble((ProviderStats stats) ->
                        percentage(stats.eligibilityCorrectRuns, stats.eligibilityEvaluatedRuns))
                .reversed()
                .thenComparing(
                        Comparator.comparingDouble((ProviderStats stats) ->
                                percentage(stats.classificationCorrectRuns, stats.classificationEvaluatedRuns))
                                .reversed()
                )
                .thenComparing(
                        Comparator.comparingDouble(this::macroClassificationAccuracy).reversed()
                )
                .thenComparingDouble(stats -> percentage(stats.reviewRuns, stats.runs))
                .thenComparingDouble(stats -> average(stats.responseTimes))
                .thenComparing(stats -> stats.provider);
    }

    private List<ClassProviderPerformanceResponse> classPerformance(DashboardContext context) {
        List<ClassProviderPerformanceResponse> rows = new ArrayList<>();

        context.providerStats.values().stream()
                .sorted(Comparator.comparing(stats -> stats.provider))
                .forEach(providerStats -> providerStats.classStats.values().stream()
                        .sorted(Comparator.comparing(stats -> stats.expectedClass))
                        .forEach(stats -> rows.add(new ClassProviderPerformanceResponse(
                                stats.expectedClass,
                                providerStats.provider,
                                stats.evaluatedRuns,
                                stats.correctRuns,
                                stats.wrongClassRuns,
                                stats.unclassifiedRuns,
                                percentage(stats.correctRuns, stats.evaluatedRuns),
                                percentage(
                                        stats.evaluatedRuns - stats.unclassifiedRuns,
                                        stats.evaluatedRuns
                                ),
                                average(stats.responseTimes)
                        ))));

        return rows;
    }

    private List<ClassErrorSummaryResponse> classErrors(DashboardContext context) {
        return context.errorStats.values().stream()
                .flatMap(providerErrors -> providerErrors.values().stream())
                .sorted(Comparator
                        .comparingLong(ErrorStats::totalIncorrect).reversed()
                        .thenComparing(stats -> stats.expectedClass)
                        .thenComparing(stats -> stats.provider))
                .map(stats -> new ClassErrorSummaryResponse(
                        stats.expectedClass,
                        stats.provider,
                        stats.wrongClassRuns,
                        stats.unclassifiedRuns,
                        stats.totalIncorrect(),
                        stats.labelStats.values().stream()
                                .sorted(Comparator
                                        .comparingLong(LabelStats::count).reversed()
                                        .thenComparing(statsLabel -> statsLabel.label))
                                .limit(5)
                                .map(labelStats -> new LabelFrequencyResponse(
                                        labelStats.label,
                                        labelStats.count,
                                        average(labelStats.confidences)
                                ))
                                .toList()
                ))
                .toList();
    }

    private DashboardSampleQualityResponse sampleQuality(
            long totalRuns,
            long completedEvaluations,
            long pendingEvaluations,
            DashboardContext context
    ) {
        List<String> providersWithLowSample = context.providerStats.values().stream()
                .filter(stats -> stats.evaluatedRuns < MIN_EVALUATIONS_PER_PROVIDER)
                .map(stats -> stats.provider)
                .sorted()
                .toList();
        List<String> classesWithLowSample = context.classStats.values().stream()
                .filter(stats -> stats.evaluatedRuns < MIN_EVALUATIONS_PER_CLASS)
                .map(stats -> stats.expectedClass)
                .sorted()
                .toList();

        return new DashboardSampleQualityResponse(
                context.validImageValidations,
                context.invalidImageValidations,
                completedEvaluations,
                pendingEvaluations,
                context.legacyFallbackRuns,
                context.ewasteTruthRuns,
                context.nonEwasteTruthRuns,
                sum(context, stats -> stats.reviewRuns),
                sum(context, stats -> stats.classificationEvaluatedRuns),
                percentage(completedEvaluations, totalRuns),
                MIN_EVALUATIONS_PER_PROVIDER,
                MIN_EVALUATIONS_PER_CLASS,
                providersWithLowSample,
                classesWithLowSample
        );
    }

    private List<DashboardAlertResponse> alerts(
            long totalImages,
            long totalRuns,
            long completedEvaluations,
            long pendingEvaluations,
            DashboardContext context
    ) {
        List<DashboardAlertResponse> alerts = new ArrayList<>();

        if (totalImages == 0) {
            alerts.add(new DashboardAlertResponse(
                    "warning",
                    "Sem imagens testadas",
                    "Envie imagens e execute pelo menos dois providers para iniciar a comparação."
            ));
        }

        if (completedEvaluations == 0 && totalRuns > 0) {
            alerts.add(new DashboardAlertResponse(
                    "warning",
                    "Sem validações humanas válidas",
                    "Valide as imagens para habilitar as métricas de detecção e classificação."
            ));
        }

        if (totalRuns > 0 && percentage(pendingEvaluations, totalRuns) > 20.0) {
            alerts.add(new DashboardAlertResponse(
                    "warning",
                    "Fila de validação alta",
                    "Mais de 20% das execuções ainda não possuem validação humana válida."
            ));
        }

        context.providerStats.values().stream()
                .filter(stats -> stats.evaluatedRuns > 0 && stats.evaluatedRuns < MIN_EVALUATIONS_PER_PROVIDER)
                .sorted(Comparator.comparing(stats -> stats.provider))
                .forEach(stats -> alerts.add(new DashboardAlertResponse(
                        "info",
                        "Amostra baixa por provider",
                        stats.provider + " possui " + stats.evaluatedRuns + " execução(ões) avaliada(s); use pelo menos "
                                + MIN_EVALUATIONS_PER_PROVIDER + " para comparar com mais segurança."
                )));

        context.classStats.values().stream()
                .filter(stats -> stats.evaluatedRuns > 0 && stats.evaluatedRuns < MIN_EVALUATIONS_PER_CLASS)
                .sorted(Comparator.comparing(stats -> stats.expectedClass))
                .forEach(stats -> alerts.add(new DashboardAlertResponse(
                        "info",
                        "Amostra baixa por classe",
                        stats.expectedClass + " possui " + stats.evaluatedRuns
                                + " execução(ões) avaliada(s); inclua mais exemplos dessa classe."
                )));

        context.providerStats.values().stream()
                .filter(stats -> stats.runs > 0 && percentage(stats.reviewRuns, stats.runs) > 25.0)
                .sorted(Comparator.comparing(stats -> stats.provider))
                .forEach(stats -> alerts.add(new DashboardAlertResponse(
                        "warning",
                        "Taxa de REVIEW elevada",
                        stats.provider + " tem " + percentage(stats.reviewRuns, stats.runs)
                                + "% das execuções marcadas para revisão."
                )));

        if (alerts.isEmpty()) {
            alerts.add(new DashboardAlertResponse(
                    "success",
                    "Amostra operacional",
                    "Os dados atuais já permitem uma comparação inicial entre providers."
            ));
        }

        return alerts;
    }

    private List<ProviderSummaryResponse> providerSummaries(DashboardContext context) {
        return context.providerStats.values().stream()
                .sorted(Comparator.comparing(stats -> stats.provider))
                .map(stats -> new ProviderSummaryResponse(
                        stats.provider,
                        stats.runs,
                        average(stats.responseTimes)
                ))
                .toList();
    }

    private List<ClassSummaryResponse> classSummaries(DashboardContext context) {
        return context.classStats.values().stream()
                .sorted(Comparator.comparing(stats -> stats.expectedClass))
                .map(stats -> new ClassSummaryResponse(
                        stats.expectedClass,
                        stats.evaluatedRuns,
                        stats.correctRuns,
                        percentage(stats.correctRuns, stats.evaluatedRuns)
                ))
                .toList();
    }

    private double macroClassificationAccuracy(ProviderStats providerStats) {
        return average(providerStats.classStats.values().stream()
                .filter(stats -> stats.evaluatedRuns > 0)
                .map(stats -> percentage(stats.correctRuns, stats.evaluatedRuns))
                .toList());
    }

    private long sum(DashboardContext context, ToLongFunction<ProviderStats> mapper) {
        return context.providerStats.values().stream().mapToLong(mapper).sum();
    }

    private double percentage(long numerator, long denominator) {
        if (denominator == 0) {
            return 0.0;
        }
        return round(((double) numerator / denominator) * 100.0);
    }

    private double average(List<Double> values) {
        if (values.isEmpty()) {
            return 0.0;
        }
        return round(values.stream().mapToDouble(Double::doubleValue).average().orElse(0.0));
    }

    private double percentile(List<Double> sortedValues, int percentile) {
        if (sortedValues.isEmpty()) {
            return 0.0;
        }
        if (sortedValues.size() == 1) {
            return round(sortedValues.getFirst());
        }

        double index = (percentile / 100.0) * (sortedValues.size() - 1);
        int lowerIndex = (int) Math.floor(index);
        int upperIndex = (int) Math.ceil(index);

        if (lowerIndex == upperIndex) {
            return round(sortedValues.get(lowerIndex));
        }

        double lower = sortedValues.get(lowerIndex);
        double upper = sortedValues.get(upperIndex);
        double weight = index - lowerIndex;
        return round(lower + (upper - lower) * weight);
    }

    private double round(double value) {
        return Math.round(value * 100.0) / 100.0;
    }

    private static class DashboardContext {
        private final Map<String, ProviderStats> providerStats = new LinkedHashMap<>();
        private final Map<String, ClassStats> classStats = new HashMap<>();
        private final Map<String, Map<String, ErrorStats>> errorStats = new HashMap<>();
        private long validImageValidations;
        private long invalidImageValidations;
        private long legacyFallbackRuns;
        private long ewasteTruthRuns;
        private long nonEwasteTruthRuns;
    }

    private static class ProviderStats {
        private final String provider;
        private long runs;
        private long evaluatedRuns;
        private long eligibilityEvaluatedRuns;
        private long eligibilityCorrectRuns;
        private long truePositives;
        private long falsePositives;
        private long falseNegatives;
        private long reviewRuns;
        private long classificationEvaluatedRuns;
        private long classificationCorrectRuns;
        private long specificallyClassifiedRuns;
        private final List<Double> responseTimes = new ArrayList<>();
        private final Map<String, ClassStats> classStats = new HashMap<>();

        private ProviderStats(String provider) {
            this.provider = provider;
        }

        private void recordLatency(ProviderRun providerRun) {
            if (providerRun.getResponseTimeMs() != null) {
                responseTimes.add(providerRun.getResponseTimeMs().doubleValue());
            }
        }

        private void record(RunAssessment assessment) {
            evaluatedRuns++;
            ProviderRun providerRun = assessment.providerRun();

            if (providerRun.getEwasteEligibility() != EwasteEligibility.REVIEW) {
                eligibilityEvaluatedRuns++;
                if (Boolean.TRUE.equals(assessment.eligibilityCorrect())) {
                    eligibilityCorrectRuns++;
                }
                if (providerRun.getEwasteEligibility() == EwasteEligibility.ELIGIBLE) {
                    if (assessment.humanIsEwaste()) {
                        truePositives++;
                    } else {
                        falsePositives++;
                    }
                } else if (assessment.humanIsEwaste()) {
                    falseNegatives++;
                }
            }

            if (assessment.humanClass() != null) {
                classificationEvaluatedRuns++;
                if (assessment.specificClassification()) {
                    specificallyClassifiedRuns++;
                }
                if (Boolean.TRUE.equals(assessment.classificationCorrect())) {
                    classificationCorrectRuns++;
                }
            }
        }
    }

    private static class ClassStats {
        private final String expectedClass;
        private long evaluatedRuns;
        private long correctRuns;
        private long wrongClassRuns;
        private long unclassifiedRuns;
        private final List<Double> responseTimes = new ArrayList<>();

        private ClassStats(String expectedClass) {
            this.expectedClass = expectedClass;
        }

        private void record(RunAssessment assessment) {
            evaluatedRuns++;
            if (assessment.providerRun().getResponseTimeMs() != null) {
                responseTimes.add(assessment.providerRun().getResponseTimeMs().doubleValue());
            }
            if (Boolean.TRUE.equals(assessment.classificationCorrect())) {
                correctRuns++;
            } else if (assessment.specificClassification()) {
                wrongClassRuns++;
            } else {
                unclassifiedRuns++;
            }
        }
    }

    private static class ErrorStats {
        private final String expectedClass;
        private final String provider;
        private long wrongClassRuns;
        private long unclassifiedRuns;
        private final Map<String, LabelStats> labelStats = new HashMap<>();

        private ErrorStats(String expectedClass, String provider) {
            this.expectedClass = expectedClass;
            this.provider = provider;
        }

        private void record(RunAssessment assessment) {
            if (assessment.specificClassification()) {
                wrongClassRuns++;
            } else {
                unclassifiedRuns++;
            }

            assessment.providerRun().getLabels().stream()
                    .limit(3)
                    .forEach(label -> labelStats
                            .computeIfAbsent(label.getLabelName(), LabelStats::new)
                            .record(label));
        }

        private long totalIncorrect() {
            return wrongClassRuns + unclassifiedRuns;
        }
    }

    private static class LabelStats {
        private final String label;
        private long count;
        private final List<Double> confidences = new ArrayList<>();

        private LabelStats(String label) {
            this.label = label;
        }

        private void record(ProviderLabel label) {
            count++;
            confidences.add(label.getConfidence().doubleValue());
        }

        private long count() {
            return count;
        }
    }

    private record RunAssessment(
            ProviderRun providerRun,
            boolean evaluated,
            boolean legacyFallback,
            boolean humanIsEwaste,
            ClassificationCategory humanClass,
            Boolean eligibilityCorrect,
            Boolean classificationCorrect,
            boolean specificClassification
    ) {
        private static RunAssessment pending(ProviderRun providerRun) {
            return new RunAssessment(providerRun, false, false, false, null, null, null, false);
        }
    }
}
