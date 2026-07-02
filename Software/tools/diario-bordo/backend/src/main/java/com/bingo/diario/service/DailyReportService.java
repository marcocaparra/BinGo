package com.bingo.diario.service;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.bingo.diario.dto.CreateNoActivityReportRequest;
import com.bingo.diario.dto.CreateTodayReportRequest;
import com.bingo.diario.dto.DailyReportResponse;
import com.bingo.diario.exception.BusinessException;
import com.bingo.diario.exception.ResourceNotFoundException;
import com.bingo.diario.model.DailyReport;
import com.bingo.diario.model.Member;
import com.bingo.diario.model.ReportStatus;
import com.bingo.diario.repository.DailyReportRepository;
import com.bingo.diario.repository.MemberRepository;

@Service
@Transactional(readOnly = true)
public class DailyReportService {

    private static final String DUPLICATE_REPORT_MESSAGE =
            "Já existe relatório para este integrante nesta data.";

    private final DailyReportRepository dailyReportRepository;
    private final MemberRepository memberRepository;
    private final Clock clock;

    public DailyReportService(
            DailyReportRepository dailyReportRepository,
            MemberRepository memberRepository,
            Clock clock) {
        this.dailyReportRepository = dailyReportRepository;
        this.memberRepository = memberRepository;
        this.clock = clock;
    }

    public List<DailyReportResponse> listReports() {
        return dailyReportRepository.findAllByOrderByReportDateDescSubmittedAtDesc()
                .stream()
                .map(DailyReportResponse::from)
                .toList();
    }

    @Transactional
    public DailyReportResponse createTodayReport(CreateTodayReportRequest request) {
        Member member = findActiveMember(request.memberId());
        LocalDate reportDate = LocalDate.now(clock);
        ensureReportDoesNotExist(member.getId(), reportDate);

        DailyReport report = new DailyReport(
                member,
                reportDate,
                request.area().trim(),
                request.title().trim(),
                request.description().trim(),
                normalizeOptional(request.problems()),
                normalizeOptional(request.solution()),
                normalizeOptional(request.nextSteps()),
                normalizeOptional(request.evidenceLinks()),
                request.timeSpentMinutes(),
                ReportStatus.SUBMITTED,
                Instant.now(clock));

        return DailyReportResponse.from(dailyReportRepository.saveAndFlush(report));
    }

    @Transactional
    public DailyReportResponse createNoActivityReport(CreateNoActivityReportRequest request) {
        Member member = findActiveMember(request.memberId());
        LocalDate reportDate = LocalDate.now(clock);
        ensureReportDoesNotExist(member.getId(), reportDate);

        String area = normalizeOptional(member.getDefaultArea());
        if (area == null) {
            area = "Não informada";
        }

        DailyReport report = new DailyReport(
                member,
                reportDate,
                area,
                "Sem atividade",
                "Integrante informou que não realizou atividades nesta data.",
                null,
                null,
                null,
                null,
                0,
                ReportStatus.NO_ACTIVITY,
                Instant.now(clock));

        return DailyReportResponse.from(dailyReportRepository.saveAndFlush(report));
    }

    private Member findActiveMember(UUID memberId) {
        return memberRepository.findByIdAndIsActiveTrue(memberId)
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Integrante não encontrado ou inativo."));
    }

    private void ensureReportDoesNotExist(UUID memberId, LocalDate reportDate) {
        if (dailyReportRepository.existsByMember_IdAndReportDate(memberId, reportDate)) {
            throw new BusinessException(DUPLICATE_REPORT_MESSAGE);
        }
    }

    private String normalizeOptional(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }
}
