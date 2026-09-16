package com.visiontester.backend.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "image_validations")
public class ImageValidation {

    @Id
    private UUID id = UUID.randomUUID();

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "image_id", nullable = false, unique = true)
    private ImageAsset image;

    @Enumerated(EnumType.STRING)
    @Column(name = "validation_status", nullable = false, length = 40)
    private ImageValidationStatus validationStatus;

    @Column(name = "human_is_ewaste")
    private Boolean humanIsEwaste;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "human_confirmed_class_id")
    private ClassificationCategory humanConfirmedClass;

    @Column(name = "human_note", columnDefinition = "text")
    private String humanNote;

    @Column(name = "validated_at", nullable = false)
    private OffsetDateTime validatedAt = OffsetDateTime.now();

    protected ImageValidation() {
    }

    public ImageValidation(ImageAsset image) {
        this.image = image;
    }

    public void update(
            ImageValidationStatus validationStatus,
            Boolean humanIsEwaste,
            ClassificationCategory humanConfirmedClass,
            String humanNote
    ) {
        this.validationStatus = validationStatus;
        this.humanIsEwaste = validationStatus == ImageValidationStatus.INVALID ? null : humanIsEwaste;
        this.humanConfirmedClass = validationStatus == ImageValidationStatus.INVALID || !Boolean.TRUE.equals(humanIsEwaste)
                ? null
                : humanConfirmedClass;
        this.humanNote = humanNote;
        this.validatedAt = OffsetDateTime.now();
    }

    public UUID getId() {
        return id;
    }

    public ImageAsset getImage() {
        return image;
    }

    public ImageValidationStatus getValidationStatus() {
        return validationStatus;
    }

    public Boolean getHumanIsEwaste() {
        return humanIsEwaste;
    }

    public ClassificationCategory getHumanConfirmedClass() {
        return humanConfirmedClass;
    }

    public String getHumanNote() {
        return humanNote;
    }

    public OffsetDateTime getValidatedAt() {
        return validatedAt;
    }
}
