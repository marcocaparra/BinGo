package com.visiontester.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.visiontester.backend.BackendApplication;
import com.visiontester.backend.api.dto.DashboardMetricsResponse;
import com.visiontester.backend.api.dto.SaveImageValidationRequest;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationStatus;
import com.visiontester.backend.domain.EvaluationResult;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.domain.HumanEvaluation;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.ImageValidationStatus;
import com.visiontester.backend.domain.Project;
import com.visiontester.backend.domain.ProviderLabel;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.domain.ProviderRunStatus;
import com.visiontester.backend.repository.ClassificationCategoryRepository;
import com.visiontester.backend.repository.HumanEvaluationRepository;
import com.visiontester.backend.repository.ImageAssetRepository;
import com.visiontester.backend.repository.ProjectRepository;
import com.visiontester.backend.repository.ProviderRunRepository;
import java.math.BigDecimal;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.ObjectMapper;

class DashboardServiceIntegrationTests {

    @Test
    void dashboardUsesImageTruthAndMatchesDirectPostgresAggregation() {
        try (ConfigurableApplicationContext context = startContext()) {
            ProjectRepository projectRepository = context.getBean(ProjectRepository.class);
            ImageAssetRepository imageRepository = context.getBean(ImageAssetRepository.class);
            ProviderRunRepository runRepository = context.getBean(ProviderRunRepository.class);
            HumanEvaluationRepository evaluationRepository = context.getBean(HumanEvaluationRepository.class);
            ClassificationCategoryRepository categoryRepository =
                    context.getBean(ClassificationCategoryRepository.class);
            ImageValidationService validationService = context.getBean(ImageValidationService.class);
            DashboardService dashboardService = context.getBean(DashboardService.class);
            JdbcTemplate jdbcTemplate = context.getBean(JdbcTemplate.class);
            ObjectMapper objectMapper = context.getBean(ObjectMapper.class);

            Project project = projectRepository.save(new Project(
                    "dashboard-v9-" + UUID.randomUUID(),
                    "Dashboard V9 integration test"
            ));

            try {
                ClassificationCategory cable = categoryRepository.findByCodeIgnoreCase("CABLE").orElseThrow();
                ClassificationCategory battery = categoryRepository.findByCodeIgnoreCase("BATTERY").orElseThrow();

                ImageAsset ewasteImage = imageRepository.save(image(project, "ewaste.png"));
                ProviderRun awsCorrect = run(
                        runRepository,
                        objectMapper,
                        ewasteImage,
                        "AWS TEST",
                        EwasteEligibility.ELIGIBLE,
                        cable,
                        100
                );
                ProviderRun googleWrong = run(
                        runRepository,
                        objectMapper,
                        ewasteImage,
                        "GOOGLE TEST",
                        EwasteEligibility.NOT_ELIGIBLE,
                        battery,
                        200
                );
                validationService.save(
                        ewasteImage.getId(),
                        validation(true, cable, "two providers, one image truth")
                );

                ImageAsset nonEwasteImage = imageRepository.save(image(project, "non-ewaste.png"));
                run(
                        runRepository,
                        objectMapper,
                        nonEwasteImage,
                        "AWS TEST",
                        EwasteEligibility.NOT_ELIGIBLE,
                        null,
                        110
                );
                run(
                        runRepository,
                        objectMapper,
                        nonEwasteImage,
                        "GOOGLE TEST",
                        EwasteEligibility.ELIGIBLE,
                        null,
                        210
                );
                validationService.save(
                        nonEwasteImage.getId(),
                        validation(false, null, "binary truth without class")
                );

                ImageAsset reviewImage = imageRepository.save(image(project, "review.png"));
                run(
                        runRepository,
                        objectMapper,
                        reviewImage,
                        "AWS TEST",
                        EwasteEligibility.REVIEW,
                        cable,
                        120
                );
                validationService.save(
                        reviewImage.getId(),
                        validation(true, cable, "REVIEW is separate from binary accuracy")
                );

                ImageAsset pendingImage = imageRepository.save(image(project, "pending.png"));
                run(
                        runRepository,
                        objectMapper,
                        pendingImage,
                        "AWS TEST",
                        EwasteEligibility.ELIGIBLE,
                        cable,
                        130
                );

                ImageAsset legacyImage = imageRepository.save(image(project, "legacy.png"));
                ProviderRun legacyRun = run(
                        runRepository,
                        objectMapper,
                        legacyImage,
                        "GOOGLE TEST",
                        EwasteEligibility.ELIGIBLE,
                        cable,
                        220
                );
                evaluationRepository.save(new HumanEvaluation(
                        legacyRun,
                        cable,
                        EvaluationResult.CORRECT,
                        true,
                        "legacy fallback without image_validation"
                ));

                DashboardMetricsResponse metrics = dashboardService.metrics(project.getId());

                assertEquals(5, metrics.totalImages());
                assertEquals(7, metrics.totalProviderRuns());
                assertEquals(6, metrics.completedEvaluations());
                assertEquals(1, metrics.pendingEvaluations());
                assertEquals(5, metrics.eligibilityEvaluatedRuns());
                assertEquals(3, metrics.eligibilityCorrectRuns());
                assertEquals(60.0, metrics.eligibilityAccuracyRate());
                assertEquals(66.67, metrics.precisionRate());
                assertEquals(66.67, metrics.recallRate());
                assertEquals(1, metrics.falsePositives());
                assertEquals(1, metrics.falseNegatives());
                assertEquals(1, metrics.reviewRuns());
                assertEquals(4, metrics.classificationEvaluatedRuns());
                assertEquals(3, metrics.classificationCorrectRuns());
                assertEquals(75.0, metrics.classificationAccuracyRate());
                assertEquals(85.71, metrics.sampleQuality().evaluationCoverageRate());
                assertEquals(1, metrics.sampleQuality().legacyFallbackRuns());

                assertEquals("AWS TEST", metrics.providerComparisons().getFirst().provider());
                var aws = metrics.providerComparisons().stream()
                        .filter(provider -> provider.provider().equals("AWS TEST"))
                        .findFirst()
                        .orElseThrow();
                var google = metrics.providerComparisons().stream()
                        .filter(provider -> provider.provider().equals("GOOGLE TEST"))
                        .findFirst()
                        .orElseThrow();
                assertEquals(3, aws.evaluatedRuns());
                assertEquals(100.0, aws.eligibilityAccuracyRate());
                assertEquals(100.0, aws.classificationAccuracyRate());
                assertEquals(3, google.evaluatedRuns());
                assertEquals(33.33, google.eligibilityAccuracyRate());
                assertEquals(50.0, google.classificationAccuracyRate());

                var cableSummary = metrics.classes().stream()
                        .filter(row -> row.expectedClass().equals("CABLE"))
                        .findFirst()
                        .orElseThrow();
                assertEquals(4, cableSummary.evaluations());
                assertEquals(3, cableSummary.correctEvaluations());
                assertEquals(75.0, cableSummary.accuracyRate());

                var googleCable = metrics.classPerformance().stream()
                        .filter(row -> row.expectedClass().equals("CABLE"))
                        .filter(row -> row.provider().equals("GOOGLE TEST"))
                        .findFirst()
                        .orElseThrow();
                assertEquals(2, googleCable.evaluatedRuns());
                assertEquals(1, googleCable.correctRuns());
                assertEquals(1, googleCable.wrongClassRuns());
                assertEquals(0, googleCable.unclassifiedRuns());

                var classError = metrics.classErrors().stream()
                        .filter(row -> row.expectedClass().equals("CABLE"))
                        .filter(row -> row.provider().equals("GOOGLE TEST"))
                        .findFirst()
                        .orElseThrow();
                assertEquals(1, classError.totalIncorrectRuns());
                assertEquals(1, classError.wrongClassRuns());

                Map<String, Object> sqlMetrics = directPostgresMetrics(jdbcTemplate, project.getId());
                assertEquals(((Number) sqlMetrics.get("total_runs")).longValue(), metrics.totalProviderRuns());
                assertEquals(((Number) sqlMetrics.get("evaluated_runs")).longValue(), metrics.completedEvaluations());
                assertEquals(((Number) sqlMetrics.get("pending_runs")).longValue(), metrics.pendingEvaluations());
                assertEquals(
                        ((Number) sqlMetrics.get("eligibility_evaluated")).longValue(),
                        metrics.eligibilityEvaluatedRuns()
                );
                assertEquals(
                        ((Number) sqlMetrics.get("eligibility_correct")).longValue(),
                        metrics.eligibilityCorrectRuns()
                );
                assertEquals(
                        ((Number) sqlMetrics.get("classification_evaluated")).longValue(),
                        metrics.classificationEvaluatedRuns()
                );
                assertEquals(
                        ((Number) sqlMetrics.get("classification_correct")).longValue(),
                        metrics.classificationCorrectRuns()
                );

                ProviderRun persistedAws = runRepository.findById(awsCorrect.getId()).orElseThrow();
                ProviderRun persistedGoogle = runRepository.findById(googleWrong.getId()).orElseThrow();
                assertEquals(Boolean.TRUE, persistedAws.getEligibilityCorrect());
                assertEquals(Boolean.TRUE, persistedAws.getClassificationCorrect());
                assertEquals(Boolean.FALSE, persistedGoogle.getEligibilityCorrect());
                assertEquals(Boolean.FALSE, persistedGoogle.getClassificationCorrect());
            } finally {
                projectRepository.deleteById(project.getId());
            }
        }
    }

    private Map<String, Object> directPostgresMetrics(JdbcTemplate jdbcTemplate, UUID projectId) {
        return jdbcTemplate.queryForMap("""
                WITH truth AS (
                    SELECT
                        pr.id,
                        pr.ewaste_eligibility,
                        pr.suggested_class_id,
                        COALESCE(iv.human_is_ewaste, he.is_target_object) AS human_is_ewaste,
                        COALESCE(
                            iv.human_confirmed_class_id,
                            CASE WHEN he.is_target_object THEN he.correct_class_id END
                        ) AS human_class_id,
                        CASE
                            WHEN iv.validation_status = 'VALID' THEN TRUE
                            WHEN iv.id IS NULL AND he.id IS NOT NULL THEN TRUE
                            ELSE FALSE
                        END AS evaluated
                    FROM provider_runs pr
                    JOIN images image ON image.id = pr.image_id
                    LEFT JOIN image_validations iv ON iv.image_id = image.id
                    LEFT JOIN human_evaluations he ON he.provider_run_id = pr.id
                    WHERE image.project_id = ?
                )
                SELECT
                    count(*) AS total_runs,
                    count(*) FILTER (WHERE evaluated) AS evaluated_runs,
                    count(*) FILTER (WHERE NOT evaluated) AS pending_runs,
                    count(*) FILTER (
                        WHERE evaluated AND ewaste_eligibility <> 'REVIEW'
                    ) AS eligibility_evaluated,
                    count(*) FILTER (
                        WHERE evaluated
                          AND ewaste_eligibility <> 'REVIEW'
                          AND (
                              (ewaste_eligibility = 'ELIGIBLE' AND human_is_ewaste)
                              OR
                              (ewaste_eligibility = 'NOT_ELIGIBLE' AND NOT human_is_ewaste)
                          )
                    ) AS eligibility_correct,
                    count(*) FILTER (
                        WHERE evaluated AND human_class_id IS NOT NULL
                    ) AS classification_evaluated,
                    count(*) FILTER (
                        WHERE evaluated
                          AND human_class_id IS NOT NULL
                          AND suggested_class_id = human_class_id
                    ) AS classification_correct
                FROM truth
                """, projectId);
    }

    private SaveImageValidationRequest validation(
            boolean humanIsEwaste,
            ClassificationCategory humanClass,
            String note
    ) {
        return new SaveImageValidationRequest(
                ImageValidationStatus.VALID,
                humanIsEwaste,
                humanClass == null ? null : humanClass.getId(),
                note
        );
    }

    private ProviderRun run(
            ProviderRunRepository repository,
            ObjectMapper objectMapper,
            ImageAsset image,
            String provider,
            EwasteEligibility eligibility,
            ClassificationCategory suggestedClass,
            int responseTimeMs
    ) {
        ProviderRun run = new ProviderRun(
                image,
                provider,
                ProviderRunStatus.MANUAL,
                responseTimeMs,
                objectMapper.createObjectNode()
        );
        run.addLabel(new ProviderLabel(
                suggestedClass == null ? "Unknown" : suggestedClass.getName(),
                new BigDecimal("90.000")
        ));
        run.applyClassification(
                suggestedClass,
                suggestedClass == null ? ClassificationStatus.NO_MATCH : ClassificationStatus.CLASSIFIED,
                suggestedClass == null ? BigDecimal.ZERO : new BigDecimal("90.000"),
                suggestedClass == null ? BigDecimal.ZERO : new BigDecimal("80.000"),
                "dashboard-test",
                objectMapper.createArrayNode(),
                eligibility
        );
        return repository.save(run);
    }

    private ImageAsset image(Project project, String filename) {
        return new ImageAsset(
                project,
                filename,
                filename,
                "integration-test/" + filename,
                "image/png",
                1,
                "0".repeat(64),
                1,
                1
        );
    }

    private ConfigurableApplicationContext startContext() {
        return new SpringApplicationBuilder(BackendApplication.class)
                .web(WebApplicationType.NONE)
                .properties(
                        "spring.main.banner-mode=off",
                        "spring.devtools.restart.enabled=false"
                )
                .run();
    }
}
