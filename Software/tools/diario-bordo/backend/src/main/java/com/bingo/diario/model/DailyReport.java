package com.bingo.diario.model;

import java.time.Instant;
import java.time.LocalDate;
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
import jakarta.persistence.Table;

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
}
