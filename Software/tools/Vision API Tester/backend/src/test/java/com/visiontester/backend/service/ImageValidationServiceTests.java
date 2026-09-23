package com.visiontester.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationStatus;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.ImageValidation;
import com.visiontester.backend.domain.ImageValidationStatus;
import com.visiontester.backend.domain.Project;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.domain.ProviderRunStatus;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;

class ImageValidationServiceTests {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void evaluatesEligibilityAndSpecificClassIndependently() {
        ClassificationCategory charger = new ClassificationCategory("CHARGER", "Charger", 50);
        ClassificationCategory cable = new ClassificationCategory("CABLE", "Cable", 40);
        ImageAsset image = image();
        ImageValidation validation = validation(image, true, charger);
        ProviderRun correct = run(image, "AWS", EwasteEligibility.ELIGIBLE, charger);
        ProviderRun wrongClass = run(image, "GOOGLE", EwasteEligibility.ELIGIBLE, cable);

        ImageValidationService.applyCorrectness(correct, validation);
        ImageValidationService.applyCorrectness(wrongClass, validation);

        assertTrue(correct.getEligibilityCorrect());
        assertTrue(correct.getClassificationCorrect());
        assertTrue(wrongClass.getEligibilityCorrect());
        assertFalse(wrongClass.getClassificationCorrect());
    }

    @Test
    void nonElectronicAndReviewRemainIndependent() {
        ImageAsset image = image();
        ImageValidation validation = validation(image, false, null);
        ProviderRun notEligible = run(image, "AWS", EwasteEligibility.NOT_ELIGIBLE, null);
        ProviderRun review = run(image, "GOOGLE", EwasteEligibility.REVIEW, null);

        ImageValidationService.applyCorrectness(notEligible, validation);
        ImageValidationService.applyCorrectness(review, validation);

        assertTrue(notEligible.getEligibilityCorrect());
        assertNull(notEligible.getClassificationCorrect());
        assertNull(review.getEligibilityCorrect());
        assertNull(review.getClassificationCorrect());
    }

    @Test
    void invalidImageDoesNotScoreEitherProviderDecision() {
        ImageAsset image = image();
        ImageValidation validation = new ImageValidation(image);
        validation.update(ImageValidationStatus.INVALID, null, null, null);
        ProviderRun providerRun = run(
                image,
                "AWS",
                EwasteEligibility.ELIGIBLE,
                new ClassificationCategory("CHARGER", "Charger", 50)
        );

        ImageValidationService.applyCorrectness(providerRun, validation);

        assertNull(providerRun.getEligibilityCorrect());
        assertNull(providerRun.getClassificationCorrect());
    }

    @Test
    void missingSpecificTruthDoesNotTurnEligibilitySuccessIntoClassFailure() {
        ImageAsset image = image();
        ImageValidation validation = validation(image, true, null);
        ProviderRun providerRun = run(image, "AWS", EwasteEligibility.ELIGIBLE, null);

        ImageValidationService.applyCorrectness(providerRun, validation);

        assertTrue(providerRun.getEligibilityCorrect());
        assertNull(providerRun.getClassificationCorrect());
    }

    private ImageValidation validation(
            ImageAsset image,
            boolean humanIsEwaste,
            ClassificationCategory confirmedClass
    ) {
        ImageValidation validation = new ImageValidation(image);
        validation.update(ImageValidationStatus.VALID, humanIsEwaste, confirmedClass, null);
        return validation;
    }

    private ProviderRun run(
            ImageAsset image,
            String provider,
            EwasteEligibility eligibility,
            ClassificationCategory suggestedClass
    ) {
        ProviderRun providerRun = new ProviderRun(
                image,
                provider,
                ProviderRunStatus.MANUAL,
                1,
                objectMapper.createObjectNode()
        );
        providerRun.applyClassification(
                suggestedClass,
                suggestedClass == null ? ClassificationStatus.NO_MATCH : ClassificationStatus.CLASSIFIED,
                BigDecimal.ZERO.setScale(3),
                BigDecimal.ZERO.setScale(3),
                "ewaste-rules-v3",
                objectMapper.createArrayNode(),
                eligibility
        );
        return providerRun;
    }

    private ImageAsset image() {
        return new ImageAsset(
                new Project("validation-test", "test"),
                "image.png",
                "image.png",
                "test/image.png",
                "image/png",
                1,
                "0000000000000000000000000000000000000000000000000000000000000000",
                1,
                1
        );
    }
}
