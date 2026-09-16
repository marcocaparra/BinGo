package com.visiontester.backend.domain;

import jakarta.persistence.Column;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "classification_categories")
public class ClassificationCategory {

    @Id
    private UUID id = UUID.randomUUID();

    @Column(nullable = false, unique = true, length = 80)
    private String code;

    @Column(nullable = false, length = 160)
    private String name;

    @Column(name = "display_order", nullable = false)
    private int displayOrder;

    @Column(name = "is_active", nullable = false)
    private boolean active = true;

    @Enumerated(EnumType.STRING)
    @Column(name = "category_type", nullable = false, length = 40)
    private ClassificationCategoryType categoryType = ClassificationCategoryType.SPECIFIC;

    @Enumerated(EnumType.STRING)
    @Column(name = "default_ewaste_eligibility", nullable = false, length = 40)
    private EwasteEligibility defaultEwasteEligibility = EwasteEligibility.REVIEW;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @OneToMany(mappedBy = "category", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<ClassificationAlias> aliases = new ArrayList<>();

    protected ClassificationCategory() {
    }

    public ClassificationCategory(String code, String name, int displayOrder) {
        this.code = code;
        this.name = name;
        this.displayOrder = displayOrder;
    }

    public void addAlias(ClassificationAlias alias) {
        aliases.add(alias);
        alias.setCategory(this);
    }

    public void configureClassification(
            ClassificationCategoryType categoryType,
            EwasteEligibility defaultEwasteEligibility
    ) {
        this.categoryType = categoryType;
        this.defaultEwasteEligibility = defaultEwasteEligibility;
    }

    public UUID getId() {
        return id;
    }

    public String getCode() {
        return code;
    }

    public String getName() {
        return name;
    }

    public int getDisplayOrder() {
        return displayOrder;
    }

    public boolean isActive() {
        return active;
    }

    public ClassificationCategoryType getCategoryType() {
        return categoryType;
    }

    public EwasteEligibility getDefaultEwasteEligibility() {
        return defaultEwasteEligibility;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public List<ClassificationAlias> getAliases() {
        return aliases;
    }
}
