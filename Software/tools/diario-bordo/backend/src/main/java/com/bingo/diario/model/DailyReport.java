package com.bingo.diario.model;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.annotations.UpdateTimestamp;
import org.hibernate.type.SqlTypes;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import jakarta.persistence.CascadeType;

@Entity
@Table(name = "diary_reports")
public class DailyReport {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "member_id", nullable = false)
    private Member member;

    @Column(name = "report_date", nullable = false)
    private LocalDate reportDate;

    @Column(nullable = false, length = 80)
    private String area;

    @Column(nullable = false, length = 160)
    private String title;

    @Column(nullable = false, columnDefinition = "text")
    private String description;

    @Column(columnDefinition = "text")
    private String problems;

    @Column(columnDefinition = "text")
    private String solution;

    @Column(name = "next_steps", columnDefinition = "text")
    private String nextSteps;

    @Column(name = "evidence_links", columnDefinition = "text")
    private String evidenceLinks;

    @Column(name = "time_spent_minutes")
    private Integer timeSpentMinutes;

    @Column(name = "approximate_time", length = 40)
    private String approximateTime;

    @Column(columnDefinition = "text")
    private String participants;

    @Column(length = 120)
    private String environment;

    @Column(name = "record_type", length = 80)
    private String recordType;

    @Column(columnDefinition = "text")
    private String decisions;

    @Column(name = "tests_and_observations", columnDefinition = "text")
    private String testsAndObservations;

    @Column(name = "tools_used", columnDefinition = "text")
    private String toolsUsed;

    @Column(name = "pending_items", columnDefinition = "text")
    private String pendingItems;

    @Column(name = "next_step_owner", length = 120)
    private String nextStepOwner;

    @Column(name = "next_step_due_date")
    private LocalDate nextStepDueDate;

    @Column(name = "final_notes", columnDefinition = "text")
    private String finalNotes;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(nullable = false, columnDefinition = "diary_report_status")
    private ReportStatus status;

    @Column(name = "submitted_at", nullable = false)
    private Instant submittedAt;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @OneToMany(mappedBy = "report", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<ReportAttachment> attachments = new ArrayList<>();

    protected DailyReport() {
    }

    public DailyReport(
            Member member,
            LocalDate reportDate,
            String area,
            String title,
            String description,
            String problems,
            String solution,
            String nextSteps,
            String evidenceLinks,
            Integer timeSpentMinutes,
            String approximateTime,
            String participants,
            String environment,
            String recordType,
            String decisions,
            String testsAndObservations,
            String toolsUsed,
            String pendingItems,
            String nextStepOwner,
            LocalDate nextStepDueDate,
            String finalNotes,
            ReportStatus status,
            Instant submittedAt) {
        this.member = member;
        this.reportDate = reportDate;
        this.area = area;
        this.title = title;
        this.description = description;
        this.problems = problems;
        this.solution = solution;
        this.nextSteps = nextSteps;
        this.evidenceLinks = evidenceLinks;
        this.timeSpentMinutes = timeSpentMinutes;
        this.approximateTime = approximateTime;
        this.participants = participants;
        this.environment = environment;
        this.recordType = recordType;
        this.decisions = decisions;
        this.testsAndObservations = testsAndObservations;
        this.toolsUsed = toolsUsed;
        this.pendingItems = pendingItems;
        this.nextStepOwner = nextStepOwner;
        this.nextStepDueDate = nextStepDueDate;
        this.finalNotes = finalNotes;
        this.status = status;
        this.submittedAt = submittedAt;
    }

    public UUID getId() {
        return id;
    }

    public Member getMember() {
        return member;
    }

    public LocalDate getReportDate() {
        return reportDate;
    }

    public String getArea() {
        return area;
    }

    public String getTitle() {
        return title;
    }

    public String getDescription() {
        return description;
    }

    public String getProblems() {
        return problems;
    }

    public String getSolution() {
        return solution;
    }

    public String getNextSteps() {
        return nextSteps;
    }

    public String getEvidenceLinks() {
        return evidenceLinks;
    }

    public Integer getTimeSpentMinutes() {
        return timeSpentMinutes;
    }

    public String getApproximateTime() {
        return approximateTime;
    }

    public String getParticipants() {
        return participants;
    }

    public String getEnvironment() {
        return environment;
    }

    public String getRecordType() {
        return recordType;
    }

    public String getDecisions() {
        return decisions;
    }

    public String getTestsAndObservations() {
        return testsAndObservations;
    }

    public String getToolsUsed() {
        return toolsUsed;
    }

    public String getPendingItems() {
        return pendingItems;
    }

    public String getNextStepOwner() {
        return nextStepOwner;
    }

    public LocalDate getNextStepDueDate() {
        return nextStepDueDate;
    }

    public String getFinalNotes() {
        return finalNotes;
    }

    public ReportStatus getStatus() {
        return status;
    }

    public Instant getSubmittedAt() {
        return submittedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public List<ReportAttachment> getAttachments() {
        return attachments;
    }

    public void updateContent(
            String area,
            String title,
            String description,
            String problems,
            String evidenceLinks,
            String participants,
            String environment,
            String recordType,
            String decisions,
            String testsAndObservations,
            String toolsUsed,
            String pendingItems,
            String finalNotes) {
        this.area = area;
        this.title = title;
        this.description = description;
        this.problems = problems;
        this.evidenceLinks = evidenceLinks;
        this.participants = participants;
        this.environment = environment;
        this.recordType = recordType;
        this.decisions = decisions;
        this.testsAndObservations = testsAndObservations;
        this.toolsUsed = toolsUsed;
        this.pendingItems = pendingItems;
        this.finalNotes = finalNotes;
    }
}
