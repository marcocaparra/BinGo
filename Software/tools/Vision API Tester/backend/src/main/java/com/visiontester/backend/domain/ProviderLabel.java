package com.visiontester.backend.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.util.UUID;

@Entity
@Table(name = "provider_labels")
public class ProviderLabel {

    @Id
    private UUID id = UUID.randomUUID();

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "provider_run_id", nullable = false)
    private ProviderRun providerRun;

    @Column(name = "label_name", nullable = false, length = 180)
    private String labelName;

    @Column(nullable = false, precision = 7, scale = 3)
    private BigDecimal confidence;

    protected ProviderLabel() {
    }

    public ProviderLabel(String labelName, BigDecimal confidence) {
        this.labelName = labelName;
        this.confidence = confidence;
    }

    void setProviderRun(ProviderRun providerRun) {
        this.providerRun = providerRun;
    }

    public UUID getId() {
        return id;
    }

    public String getLabelName() {
        return labelName;
    }

    public BigDecimal getConfidence() {
        return confidence;
    }
}
