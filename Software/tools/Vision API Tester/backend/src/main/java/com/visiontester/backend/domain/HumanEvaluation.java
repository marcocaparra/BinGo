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
@Table(name = "human_evaluations")
public class HumanEvaluation {

    @Id
    private UUID id = UUID.randomUUID();

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "provider_run_id", nullable = false, unique = true)
    private ProviderRun providerRun;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "correct_class_id", nullable = false)
    private ClassificationCategory correctClass;

    @Enumerated(EnumType.STRING)
    @Column(name = "evaluation_result", nullable = false, length = 40)
    private EvaluationResult evaluationResult;

    @Column(name = "is_target_object", nullable = false)
    private boolean targetObject;

    @Column(name = "human_note", columnDefinition = "text")
    private String humanNote;

    @Column(name = "evaluated_at", nullable = false)
    private OffsetDateTime evaluatedAt = OffsetDateTime.now();

    protected HumanEvaluation() {
    }

    public HumanEvaluation(
            ProviderRun providerRun,
            ClassificationCategory correctClass,
            EvaluationResult evaluationResult,
            boolean targetObject,
            String humanNote
    ) {
        this.providerRun = providerRun;
        this.correctClass = correctClass;
        this.evaluationResult = evaluationResult;
        this.targetObject = targetObject;
        this.humanNote = humanNote;
    }

    public void update(ClassificationCategory correctClass, EvaluationResult evaluationResult, boolean targetObject, String humanNote) {
        this.correctClass = correctClass;
        this.evaluationResult = evaluationResult;
        this.targetObject = targetObject;
        this.humanNote = humanNote;
        this.evaluatedAt = OffsetDateTime.now();
    }

    public UUID getId() {
        return id;
    }

    public ProviderRun getProviderRun() {
        return providerRun;
    }

    public ClassificationCategory getCorrectClass() {
        return correctClass;
    }

    public EvaluationResult getEvaluationResult() {
        return evaluationResult;
    }

    public boolean isTargetObject() {
        return targetObject;
    }

    public String getHumanNote() {
        return humanNote;
    }

    public OffsetDateTime getEvaluatedAt() {
        return evaluatedAt;
    }
}
