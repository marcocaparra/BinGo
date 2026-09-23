package com.visiontester.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.visiontester.backend.BackendApplication;
import com.visiontester.backend.api.dto.SaveImageValidationRequest;
import com.visiontester.backend.domain.ClassificationStatus;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.ImageValidationStatus;
import com.visiontester.backend.domain.Project;
import com.visiontester.backend.domain.ProviderLabel;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.domain.ProviderRunStatus;
import com.visiontester.backend.repository.ClassificationCategoryRepository;
import com.visiontester.backend.repository.ImageAssetRepository;
import com.visiontester.backend.repository.ProjectRepository;
import com.visiontester.backend.repository.ProviderRunRepository;
import java.math.BigDecimal;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import tools.jackson.databind.ObjectMapper;

class ProviderRunEligibilityPersistenceIntegrationTests {

    @Test
    void imageTruthAndIndependentProviderAccuracySurviveContextRestartAndFeedDashboard() {
        UUID projectId;
        UUID providerRunId;
        UUID wrongProviderRunId;

        try (ConfigurableApplicationContext firstContext = startContext()) {
            ProjectRepository projectRepository = firstContext.getBean(ProjectRepository.class);
            ImageAssetRepository imageRepository = firstContext.getBean(ImageAssetRepository.class);
            ProviderRunRepository providerRunRepository = firstContext.getBean(ProviderRunRepository.class);
            ClassificationCategoryRepository categoryRepository = firstContext.getBean(ClassificationCategoryRepository.class);
            ObjectMapper objectMapper = firstContext.getBean(ObjectMapper.class);

            Project project = projectRepository.save(new Project(
                    "eligibility-context-restart-" + UUID.randomUUID(),
                    "Integration test"
            ));
            ImageAsset image = imageRepository.save(new ImageAsset(
                    project,
                    "eligibility-test.png",
                    "eligibility-test.png",
                    "integration-test/eligibility-test.png",
                    "image/png",
                    1,
                    "0000000000000000000000000000000000000000000000000000000000000000",
                    1,
                    1
            ));
            var charger = categoryRepository.findByCodeIgnoreCase("CHARGER").orElseThrow();
            var invalid = categoryRepository.findByCodeIgnoreCase("INVALID").orElseThrow();
            ProviderRun providerRun = new ProviderRun(
                    image,
                    "INTEGRATION TEST",
                    ProviderRunStatus.MANUAL,
                    1,
                    objectMapper.createObjectNode()
            );
            providerRun.addLabel(new ProviderLabel("Battery charger", new BigDecimal("100.000")));
            providerRun.applyClassification(
                    charger,
                    ClassificationStatus.CLASSIFIED,
                    new BigDecimal("100.000"),
                    new BigDecimal("100.000"),
                    "ewaste-rules-v3",
                    objectMapper.createArrayNode(),
                    EwasteEligibility.ELIGIBLE
            );
            providerRun = providerRunRepository.save(providerRun);
            ProviderRun wrongProviderRun = new ProviderRun(
                    image,
                    "GOOGLE INTEGRATION",
                    ProviderRunStatus.MANUAL,
                    2,
                    objectMapper.createObjectNode()
            );
            wrongProviderRun.addLabel(new ProviderLabel("Invalid", new BigDecimal("100.000")));
            wrongProviderRun.applyClassification(
                    invalid,
                    ClassificationStatus.CLASSIFIED,
                    new BigDecimal("100.000"),
                    new BigDecimal("100.000"),
                    "ewaste-rules-v3",
                    objectMapper.createArrayNode(),
                    EwasteEligibility.NOT_ELIGIBLE
            );
            wrongProviderRun = providerRunRepository.save(wrongProviderRun);
            firstContext.getBean(ImageValidationService.class).save(
                    image.getId(),
                    new SaveImageValidationRequest(
                            ImageValidationStatus.VALID,
                            true,
                            charger.getId(),
                            "Confirmed once for the image"
                    )
            );

            projectId = project.getId();
            providerRunId = providerRun.getId();
            wrongProviderRunId = wrongProviderRun.getId();
        }

        try (ConfigurableApplicationContext restartedContext = startContext()) {
            ProviderRunRepository providerRunRepository = restartedContext.getBean(ProviderRunRepository.class);
            HistoryService historyService = restartedContext.getBean(HistoryService.class);
            ProjectRepository projectRepository = restartedContext.getBean(ProjectRepository.class);

            ProviderRun reloaded = providerRunRepository.findById(providerRunId).orElseThrow();
            assertEquals(EwasteEligibility.ELIGIBLE, reloaded.getEwasteEligibility());
            assertTrue(reloaded.getEligibilityCorrect());
            assertTrue(reloaded.getClassificationCorrect());
            ProviderRun wrongReloaded = providerRunRepository.findById(wrongProviderRunId).orElseThrow();
            assertEquals(Boolean.FALSE, wrongReloaded.getEligibilityCorrect());
            assertEquals(Boolean.FALSE, wrongReloaded.getClassificationCorrect());

            var historyItem = historyService.list(projectId).getFirst();
            var historyProvider = historyItem.providerResults().stream()
                    .filter(provider -> provider.providerRunId().equals(providerRunId))
                    .findFirst()
                    .orElseThrow();
            assertEquals(providerRunId, historyProvider.providerRunId());
            assertEquals(EwasteEligibility.ELIGIBLE, historyProvider.ewasteEligibility());
            assertTrue(historyProvider.eligibilityCorrect());
            assertTrue(historyProvider.classificationCorrect());
            assertEquals(Boolean.TRUE, historyItem.imageValidation().humanIsEwaste());
            assertEquals("CHARGER", historyItem.imageValidation().humanConfirmedClass().code());

            var decisionMetrics = restartedContext.getBean(DashboardService.class)
                    .metrics(projectId)
                    .decisionMetrics();
            var correctMetrics = decisionMetrics.stream()
                    .filter(metrics -> metrics.provider().equals("INTEGRATION TEST"))
                    .findFirst()
                    .orElseThrow();
            var wrongMetrics = decisionMetrics.stream()
                    .filter(metrics -> metrics.provider().equals("GOOGLE INTEGRATION"))
                    .findFirst()
                    .orElseThrow();
            assertEquals(100.0, correctMetrics.eligibilityAccuracyRate());
            assertEquals(100.0, correctMetrics.precisionRate());
            assertEquals(100.0, correctMetrics.recallRate());
            assertEquals(100.0, correctMetrics.classificationAccuracyRate());
            assertEquals(100.0, correctMetrics.specificClassificationRate());
            assertEquals(0.0, wrongMetrics.eligibilityAccuracyRate());
            assertEquals(1, wrongMetrics.falseNegatives());
            assertEquals(0.0, wrongMetrics.classificationAccuracyRate());
            assertEquals(0.0, wrongMetrics.specificClassificationRate());

            projectRepository.deleteById(projectId);
        }
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
