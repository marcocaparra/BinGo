package com.visiontester.backend.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import tools.jackson.databind.JsonNode;

@Entity
@Table(name = "provider_runs")
public class ProviderRun {

    @Id
    private UUID id = UUID.randomUUID();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "image_id", nullable = false)
    private ImageAsset image;

    @Column(nullable = false, length = 80)
    private String provider;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 40)
    private ProviderRunStatus status;

    @Column(name = "response_time_ms")
    private Integer responseTimeMs;

    @Column(name = "raw_response", nullable = false, columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private JsonNode rawResponse;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "suggested_class_id")
    private ClassificationCategory suggestedClass;

    @Enumerated(EnumType.STRING)
    @Column(name = "classification_status", length = 40)
    private ClassificationStatus classificationStatus;

    @Column(name = "classification_score", precision = 7, scale = 3)
    private BigDecimal classificationScore;

    @Column(name = "classification_margin", precision = 7, scale = 3)
    private BigDecimal classificationMargin;

    @Column(name = "classification_engine_version", length = 80)
    private String classificationEngineVersion;

    @Column(name = "classification_evidence", nullable = false, columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private JsonNode classificationEvidence;

    @Enumerated(EnumType.STRING)
    @Column(name = "ewaste_eligibility", nullable = false, length = 40)
    private EwasteEligibility ewasteEligibility = EwasteEligibility.REVIEW;

    @Column(name = "eligibility_correct")
    private Boolean eligibilityCorrect;

    @Column(name = "classification_correct")
    private Boolean classificationCorrect;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @OneToMany(mappedBy = "providerRun", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<ProviderLabel> labels = new ArrayList<>();

    protected ProviderRun() {
    }

    public ProviderRun(
            ImageAsset image,
            String provider,
            ProviderRunStatus status,
            Integer responseTimeMs,
            JsonNode rawResponse
    ) {
        this.image = image;
        this.provider = provider;
        this.status = status;
        this.responseTimeMs = responseTimeMs;
        this.rawResponse = rawResponse;
    }

    public void addLabel(ProviderLabel label) {
        labels.add(label);
        label.setProviderRun(this);
    }

    public UUID getId() {
        return id;
    }

    public ImageAsset getImage() {
        return image;
    }

    public String getProvider() {
        return provider;
    }

    public ProviderRunStatus getStatus() {
        return status;
    }

    public Integer getResponseTimeMs() {
        return responseTimeMs;
    }

    public JsonNode getRawResponse() {
        return rawResponse;
    }

    public ClassificationCategory getSuggestedClass() {
        return suggestedClass;
    }

    public void setSuggestedClass(ClassificationCategory suggestedClass) {
        this.suggestedClass = suggestedClass;
    }

    public void applyClassification(
            ClassificationCategory suggestedClass,
            ClassificationStatus classificationStatus,
            BigDecimal classificationScore,
            BigDecimal classificationMargin,
            String classificationEngineVersion,
            JsonNode classificationEvidence,
            EwasteEligibility ewasteEligibility
    ) {
        this.suggestedClass = suggestedClass;
        this.classificationStatus = classificationStatus;
        this.classificationScore = classificationScore;
        this.classificationMargin = classificationMargin;
        this.classificationEngineVersion = classificationEngineVersion;
        this.classificationEvidence = classificationEvidence;
        this.ewasteEligibility = ewasteEligibility;
    }

    public ClassificationStatus getClassificationStatus() {
        return classificationStatus;
    }

    public BigDecimal getClassificationScore() {
        return classificationScore;
    }

    public BigDecimal getClassificationMargin() {
        return classificationMargin;
    }

    public String getClassificationEngineVersion() {
        return classificationEngineVersion;
    }

    public JsonNode getClassificationEvidence() {
        return classificationEvidence;
    }

    public EwasteEligibility getEwasteEligibility() {
        return ewasteEligibility;
    }

    public void applyHumanValidation(Boolean eligibilityCorrect, Boolean classificationCorrect) {
        this.eligibilityCorrect = eligibilityCorrect;
        this.classificationCorrect = classificationCorrect;
    }

    public Boolean getEligibilityCorrect() {
        return eligibilityCorrect;
    }

    public Boolean getClassificationCorrect() {
        return classificationCorrect;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public List<ProviderLabel> getLabels() {
        return labels;
    }
}
