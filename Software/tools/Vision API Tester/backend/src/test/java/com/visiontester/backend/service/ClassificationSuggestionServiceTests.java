package com.visiontester.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.visiontester.backend.domain.ClassificationAlias;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationCategoryType;
import com.visiontester.backend.domain.ClassificationStatus;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.domain.ProviderLabel;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class ClassificationSuggestionServiceTests {

    private final ClassificationSuggestionService service = new ClassificationSuggestionService(null);
    private final EwasteEligibilityPolicy eligibilityPolicy = new EwasteEligibilityPolicy();

    @Test
    void genericElectronicEvidenceAloneConfirmsEligibilityWithoutSpecificClass() {
        ClassificationCategory electronicDevice = electronicDevice();

        ClassificationDecision decision = service.classify(
                List.of(label("Electronics", "100.000")),
                List.of(electronicDevice)
        );

        assertEquals(ClassificationStatus.BELOW_THRESHOLD, decision.status());
        assertNull(decision.suggestedClass());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
    }

    @Test
    void aggregatedGenericEvidenceConfirmsEligibilityWithoutSpecificClass() {
        ClassificationCategory electronicDevice = electronicDevice();

        ClassificationDecision decision = service.classify(
                List.of(
                        label("Electronic device", "91.100"),
                        label("Electronic component", "87.900")
                ),
                List.of(electronicDevice)
        );

        assertEquals(ClassificationStatus.BELOW_THRESHOLD, decision.status());
        assertNull(decision.suggestedClass());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
        assertEquals(2, decision.evidence().size());
    }

    @Test
    void computerPowerSupplyLabelsConfirmEwasteWithoutInventingSpecificClass() {
        ClassificationDecision decision = service.classify(
                List.of(
                        label("Adapter", "100.000"),
                        label("Electronics", "100.000"),
                        label("Hardware", "57.500"),
                        label("Plug", "56.600")
                ),
                List.of(electronicDevice())
        );

        assertEquals(ClassificationStatus.BELOW_THRESHOLD, decision.status());
        assertNull(decision.suggestedClass());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
    }

    @Test
    void specificClassOutranksHigherGenericEvidence() {
        ClassificationCategory electronicDevice = electronicDevice();
        ClassificationCategory pcb = eligibleCategory("PCB", "Printed Circuit Board", 60, "Circuit board");

        ClassificationDecision decision = service.classify(
                List.of(
                        label("Electronics", "100.000"),
                        label("Hardware", "100.000"),
                        label("Printed Circuit Board", "73.500")
                ),
                List.of(electronicDevice, pcb)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals("PCB", decision.suggestedClass().getCode());
        assertEquals(new BigDecimal("73.500"), decision.score());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
    }

    @Test
    void chargerLabelsUseDiminishingReturnsWithoutArtificialTie() {
        ClassificationCategory electronicDevice = electronicDevice();
        ClassificationCategory charger = eligibleCategory(
                "CHARGER",
                "Charger",
                50,
                "Battery charger",
                "Power adapter",
                "AC adapter",
                "Carregador"
        );
        ClassificationCategory cable = eligibleCategory("CABLE", "Cable", 40, "Wire");
        ClassificationCategory phone = eligibleCategory("PHONE", "Phone", 70, "Mobile Phone");

        ClassificationDecision decision = service.classify(
                List.of(
                        label("Electronic device", "95.2"),
                        label("Technology", "89.5"),
                        label("Adapter", "89.4"),
                        label("Adapter", "83.6"),
                        label("Mobile Phone Charger", "72.3"),
                        label("Wire", "71.7"),
                        label("Electronics", "71.3"),
                        label("Battery charger", "70.0"),
                        label("Gadget", "66.9"),
                        label("Plastic", "61.4"),
                        label("Electronic component", "61.0"),
                        label("Electrical cable", "57.8"),
                        label("Box", "54.8"),
                        label("AC adapter", "52.4"),
                        label("Tablet Computer Charger", "50.3")
                ),
                List.of(electronicDevice, charger, cable, phone)
        );

        assertEquals(ClassificationStatus.AMBIGUOUS, decision.status());
        assertEquals("CHARGER", decision.suggestedClass().getCode());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
        assertTrue(decision.score().compareTo(BigDecimal.ZERO) > 0);
        assertTrue(decision.score().compareTo(new BigDecimal("100.000")) < 0);
        assertEquals(new BigDecimal("78.162"), decision.score());
        assertEquals(new BigDecimal("3.845"), decision.margin());
    }

    @Test
    void electricalCableAndWireRemainSpecificCable() {
        ClassificationCategory electronicDevice = electronicDevice();
        ClassificationCategory cable = eligibleCategory("CABLE", "Cable", 40, "Wire");

        ClassificationDecision decision = service.classify(
                List.of(label("Electrical cable", "86.000"), label("Wire", "80.000")),
                List.of(electronicDevice, cable)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals("CABLE", decision.suggestedClass().getCode());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
    }

    @Test
    void smartphoneRemainsSpecificPhoneWithoutGenericEvidence() {
        ClassificationCategory electronicDevice = electronicDevice();
        ClassificationCategory phone = eligibleCategory("PHONE", "Phone", 70, "Smartphone");

        ClassificationDecision decision = service.classify(
                List.of(label("Smartphone", "94.000")),
                List.of(electronicDevice, phone)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals("PHONE", decision.suggestedClass().getCode());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
    }

    @Test
    void technologyAloneDoesNotMatchGenericElectronicDevice() {
        ClassificationDecision decision = service.classify(
                List.of(label("Technology", "100.000")),
                List.of(electronicDevice())
        );

        assertEquals(ClassificationStatus.NO_MATCH, decision.status());
        assertNull(decision.suggestedClass());
        assertEquals(EwasteEligibility.REVIEW, eligibility(decision));
    }

    @Test
    void hardwareAloneDoesNotMatchComputerHardwareAlias() {
        ClassificationDecision decision = service.classify(
                List.of(label("Hardware", "100.000")),
                List.of(electronicDevice())
        );

        assertEquals(ClassificationStatus.NO_MATCH, decision.status());
        assertNull(decision.suggestedClass());
        assertEquals(EwasteEligibility.REVIEW, eligibility(decision));
    }

    @Test
    void classifiedInvalidIsNotEligible() {
        ClassificationCategory invalid = invalidCategory("Invalid", 100, "Invalid");
        ClassificationDecision decision = service.classify(
                List.of(label("Invalid", "100.000")),
                List.of(invalid)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals(EwasteEligibility.NOT_ELIGIBLE, eligibility(decision));
    }

    @Test
    void ambiguousEligibleCandidatesRemainEligible() {
        ClassificationCategory keyboard = category("KEYBOARD", "Keyboard", 30);
        ClassificationCategory charger = eligibleCategory("CHARGER", "Charger", 50, "Adapter");
        ClassificationCategory cable = eligibleCategory("CABLE", "Cable", 40, "Adapter");

        ClassificationDecision noMatch = service.classify(
                List.of(label("Technology", "100.000")),
                List.of(electronicDevice())
        );
        ClassificationDecision belowThreshold = service.classify(
                List.of(label("Keyboard", "49.000")),
                List.of(keyboard)
        );
        ClassificationDecision ambiguous = service.classify(
                List.of(label("Adapter", "80.000")),
                List.of(charger, cable)
        );

        assertEquals(EwasteEligibility.REVIEW, eligibility(noMatch));
        assertEquals(EwasteEligibility.REVIEW, eligibility(belowThreshold));
        assertEquals(ClassificationStatus.AMBIGUOUS, ambiguous.status());
        assertEquals(2, ambiguous.relevantCandidates().size());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(ambiguous));
    }

    @Test
    void ambiguousEligibleAndInvalidCandidatesRequireReview() {
        ClassificationCategory charger = eligibleCategory(
                "CHARGER",
                "Charger",
                50,
                "Shared signal"
        );
        ClassificationCategory invalid = invalidCategory("Invalid", 100, "Shared signal");

        ClassificationDecision decision = service.classify(
                List.of(label("Shared signal", "80.000")),
                List.of(charger, invalid)
        );

        assertEquals(ClassificationStatus.AMBIGUOUS, decision.status());
        assertEquals(2, decision.relevantCandidates().size());
        assertEquals(EwasteEligibility.REVIEW, eligibility(decision));
    }

    @Test
    void ambiguousInvalidCandidatesAreNotEligible() {
        ClassificationCategory firstInvalid = invalidCategory("Invalid A", 100, "Invalid signal");
        ClassificationCategory secondInvalid = invalidCategory("Invalid B", 110, "Invalid signal");

        ClassificationDecision decision = service.classify(
                List.of(label("Invalid signal", "80.000")),
                List.of(firstInvalid, secondInvalid)
        );

        assertEquals(ClassificationStatus.AMBIGUOUS, decision.status());
        assertEquals(EwasteEligibility.NOT_ELIGIBLE, eligibility(decision));
    }

    @Test
    void classifiedOtherRequiresReview() {
        ClassificationCategory other = category("OTHER", "Other", 110);
        ClassificationDecision decision = service.classify(
                List.of(label("Other", "100.000")),
                List.of(other)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals(EwasteEligibility.REVIEW, eligibility(decision));
    }

    @Test
    void classifiesByCanonicalName() {
        ClassificationCategory battery = category("BATTERY", "Battery", 10);

        ClassificationDecision decision = service.classify(
                List.of(label("Battery", "88.700")),
                List.of(battery)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals(battery, decision.suggestedClass());
        assertEquals(new BigDecimal("88.700"), decision.score());
        assertEquals("EXACT", decision.evidence().getFirst().matchType());
    }

    @Test
    void classifiesPortuguesePhraseThroughAlias() {
        ClassificationCategory battery = category("BATTERY", "Battery", 10, "Bateria");

        ClassificationDecision decision = service.classify(
                List.of(label("Bateria de lítio", "91.000")),
                List.of(battery)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals(battery, decision.suggestedClass());
        assertEquals(new BigDecimal("72.800"), decision.score());
        assertEquals("bateria", decision.evidence().getFirst().matchedTerm());
        assertEquals("PHRASE", decision.evidence().getFirst().matchType());
    }

    @Test
    void aggregatesIndependentEvidenceForTheSameClass() {
        ClassificationCategory phone = category("PHONE", "Phone", 10, "Smartphone", "Mobile phone");

        ClassificationDecision decision = service.classify(
                List.of(label("Smartphone", "70.000"), label("Mobile phone", "60.000")),
                List.of(phone)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals(new BigDecimal("73.600"), decision.score());
        assertEquals(2, decision.evidence().size());
    }

    @Test
    void classifiedChargerIsEligible() {
        ClassificationCategory charger = eligibleCategory("CHARGER", "Charger", 50, "Battery charger");

        ClassificationDecision decision = service.classify(
                List.of(label("Battery charger", "80.000")),
                List.of(charger)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals("CHARGER", decision.suggestedClass().getCode());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
    }

    @Test
    void doesNotMatchSubstringsInsideAnotherWord() {
        ClassificationCategory cable = category("CABLE", "Cable", 10);

        ClassificationDecision decision = service.classify(
                List.of(label("Cableway", "99.000")),
                List.of(cable)
        );

        assertEquals(ClassificationStatus.NO_MATCH, decision.status());
        assertNull(decision.suggestedClass());
        assertTrue(decision.evidence().isEmpty());
    }

    @Test
    void rejectsEvidenceBelowMinimumScore() {
        ClassificationCategory keyboard = category("KEYBOARD", "Keyboard", 10);

        ClassificationDecision decision = service.classify(
                List.of(label("Keyboard", "49.000")),
                List.of(keyboard)
        );

        assertEquals(ClassificationStatus.BELOW_THRESHOLD, decision.status());
        assertNull(decision.suggestedClass());
        assertEquals(new BigDecimal("49.000"), decision.score());
    }

    @Test
    void rejectsAmbiguousClassesInsideMinimumMargin() {
        ClassificationCategory charger = eligibleCategory("CHARGER", "Charger", 10, "Adapter");
        ClassificationCategory cable = eligibleCategory("CABLE", "Cable", 20, "Adapter");

        ClassificationDecision decision = service.classify(
                List.of(label("Adapter", "80.000")),
                List.of(charger, cable)
        );

        assertEquals(ClassificationStatus.AMBIGUOUS, decision.status());
        assertEquals("CHARGER", decision.suggestedClass().getCode());
        assertEquals(BigDecimal.ZERO.setScale(3), decision.margin());
    }

    @Test
    void genericEvidenceCanConfirmEligibilityForUnknownSpecificClass() {
        ClassificationCategory unknownSpecific = category(
                "SMART_GADGET",
                "Smart Gadget",
                15,
                "Mystery device"
        );
        ClassificationCategory electronicDevice = electronicDevice();

        ClassificationDecision decision = service.classify(
                List.of(label("Mystery device", "80.000"), label("Electronics", "90.000")),
                List.of(unknownSpecific, electronicDevice)
        );

        assertEquals(ClassificationStatus.CLASSIFIED, decision.status());
        assertEquals("SMART_GADGET", decision.suggestedClass().getCode());
        assertEquals(EwasteEligibility.ELIGIBLE, eligibility(decision));
    }

    private ClassificationCategory category(String code, String name, int order, String... aliases) {
        ClassificationCategory category = new ClassificationCategory(code, name, order);
        for (String alias : aliases) {
            category.addAlias(new ClassificationAlias(alias));
        }
        return category;
    }

    private ClassificationCategory eligibleCategory(String code, String name, int order, String... aliases) {
        ClassificationCategory category = category(code, name, order, aliases);
        category.configureClassification(ClassificationCategoryType.SPECIFIC, EwasteEligibility.ELIGIBLE);
        return category;
    }

    private ClassificationCategory genericEligibleCategory(String code, String name, int order, String... aliases) {
        ClassificationCategory category = category(code, name, order, aliases);
        category.configureClassification(ClassificationCategoryType.GENERIC, EwasteEligibility.ELIGIBLE);
        return category;
    }

    private ClassificationCategory invalidCategory(String name, int order, String... aliases) {
        ClassificationCategory category = category("INVALID", name, order, aliases);
        category.configureClassification(ClassificationCategoryType.FALLBACK, EwasteEligibility.NOT_ELIGIBLE);
        return category;
    }

    private ClassificationCategory electronicDevice() {
        return genericEligibleCategory(
                "ELECTRONIC_DEVICE",
                "Electronic Device",
                95,
                "Electronics",
                "Electronic device",
                "Electronic component",
                "Electronic equipment",
                "Computer hardware",
                "Consumer electronics",
                "Eletrônico",
                "Dispositivo eletrônico",
                "Componente eletrônico",
                "Equipamento eletrônico",
                "Hardware de computador",
                "Eletrônicos"
        );
    }

    private EwasteEligibility eligibility(ClassificationDecision decision) {
        return eligibilityPolicy.derive(decision);
    }

    private ProviderLabel label(String name, String confidence) {
        return new ProviderLabel(name, new BigDecimal(confidence));
    }
}
