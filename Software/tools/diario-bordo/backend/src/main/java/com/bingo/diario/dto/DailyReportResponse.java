package com.bingo.diario.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import com.bingo.diario.model.DailyReport;
import com.bingo.diario.model.ReportStatus;

public record DailyReportResponse(
        UUID id,
        UUID memberId,
        String memberName,
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
        List<ReportAttachmentResponse> attachments,
        ReportStatus status,
        Instant submittedAt,
        Instant createdAt,
        Instant updatedAt) {

    public static DailyReportResponse from(DailyReport report) {
        return new DailyReportResponse(
                report.getId(),
                report.getMember().getId(),
                report.getMember().getName(),
                report.getReportDate(),
                report.getArea(),
                report.getTitle(),
                report.getDescription(),
                report.getProblems(),
                report.getSolution(),
                report.getNextSteps(),
                report.getEvidenceLinks(),
                report.getTimeSpentMinutes(),
                report.getApproximateTime(),
                report.getParticipants(),
                report.getEnvironment(),
                report.getRecordType(),
                report.getDecisions(),
                report.getTestsAndObservations(),
                report.getToolsUsed(),
                report.getPendingItems(),
                report.getNextStepOwner(),
                report.getNextStepDueDate(),
                report.getFinalNotes(),
                report.getAttachments()
                        .stream()
                        .map(ReportAttachmentResponse::from)
                        .toList(),
                report.getStatus(),
                report.getSubmittedAt(),
                report.getCreatedAt(),
                report.getUpdatedAt());
    }
}
