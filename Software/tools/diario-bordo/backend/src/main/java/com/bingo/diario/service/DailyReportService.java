package com.bingo.diario.service;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.beans.factory.annotation.Value;

import com.bingo.diario.dto.CreateNoActivityReportRequest;
import com.bingo.diario.dto.CreateTodayReportRequest;
import com.bingo.diario.dto.DailyReportResponse;
import com.bingo.diario.dto.MemberResponse;
import com.bingo.diario.dto.ReportExistenceResponse;
import com.bingo.diario.dto.UpdateDailyReportRequest;
import com.bingo.diario.exception.BusinessException;
import com.bingo.diario.exception.InvalidRequestException;
import com.bingo.diario.exception.ResourceNotFoundException;
import com.bingo.diario.model.DailyReport;
import com.bingo.diario.model.Member;
import com.bingo.diario.model.ReportAttachment;
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
    private final ReportAttachmentService attachmentService;
    private final Clock clock;
    private final String publicBaseUrl;

    public DailyReportService(
            DailyReportRepository dailyReportRepository,
            MemberRepository memberRepository,
            ReportAttachmentService attachmentService,
            @Value("${app.public-base-url:http://127.0.0.1:8080}") String publicBaseUrl,
            Clock clock) {
        this.dailyReportRepository = dailyReportRepository;
        this.memberRepository = memberRepository;
        this.attachmentService = attachmentService;
        this.publicBaseUrl = publicBaseUrl.replaceAll("/+$", "");
        this.clock = clock;
    }

    public List<DailyReportResponse> listReports() {
        return dailyReportRepository.findAllByOrderByReportDateDescSubmittedAtDesc()
                .stream()
                .map(DailyReportResponse::from)
                .toList();
    }

    public List<DailyReportResponse> listReports(LocalDate reportDate) {
        if (reportDate == null) {
            return listReports();
        }
        ensureDateIsNotFuture(reportDate);

        return dailyReportRepository.findAllByReportDateOrderBySubmittedAtDesc(reportDate)
                .stream()
                .map(DailyReportResponse::from)
                .toList();
    }

    public ReportExistenceResponse checkReportExists(UUID memberId, LocalDate reportDate) {
        findActiveMember(memberId);
        ensureDateIsNotFuture(reportDate);
        return dailyReportRepository.findByMember_IdAndReportDate(memberId, reportDate)
                .map(report -> new ReportExistenceResponse(
                        true,
                        report.getId(),
                        report.getMember().getId(),
                        report.getMember().getName(),
                        report.getReportDate()))
                .orElseGet(() -> ReportExistenceResponse.empty(memberId, reportDate));
    }

    @Transactional
    public DailyReportResponse createTodayReport(CreateTodayReportRequest request) {
        return createTodayReport(request, List.of());
    }

    @Transactional
    public DailyReportResponse createTodayReport(CreateTodayReportRequest request, List<MultipartFile> attachments) {
        Member member = findActiveMember(request.memberId());
        LocalDate reportDate = request.reportDate();
        ensureDateIsNotFuture(reportDate);
        ensureReportDoesNotExist(member.getId(), reportDate);
        ensureEvidenceWasProvided(request.evidenceLinks(), attachments);

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
                normalizeOptional(request.approximateTime()),
                normalizeOptional(request.participants()),
                normalizeOptional(request.environment()),
                normalizeOptional(request.recordType()),
                normalizeOptional(request.decisions()),
                normalizeOptional(request.testsAndObservations()),
                normalizeOptional(request.toolsUsed()),
                normalizeOptional(request.pendingItems()),
                normalizeOptional(request.nextStepOwner()),
                request.nextStepDueDate(),
                normalizeOptional(request.finalNotes()),
                deriveStatus(reportDate),
                Instant.now(clock));

        DailyReport savedReport = dailyReportRepository.saveAndFlush(report);
        List<ReportAttachment> savedAttachments = attachmentService.storeAttachments(savedReport, attachments);
        savedReport.getAttachments().addAll(savedAttachments);

        return DailyReportResponse.from(savedReport);
    }

    @Transactional
    public DailyReportResponse createNoActivityReport(CreateNoActivityReportRequest request) {
        Member member = findActiveMember(request.memberId());
        LocalDate reportDate = request.reportDate();
        ensureDateIsNotFuture(reportDate);
        ensureReportDoesNotExist(member.getId(), reportDate);

        String area = normalizeOptional(request.area());
        if (area == null) {
            area = normalizeOptional(member.getDefaultArea());
        }
        if (area == null) {
            area = "Não informada";
        }

        DailyReport report = new DailyReport(
                member,
                reportDate,
                area,
                "Sem atividade no projeto",
                "Integrante selecionou que não trabalhou no projeto nesta data.",
                null,
                null,
                null,
                null,
                0,
                null,
                null,
                null,
                "Sem atividade",
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                ReportStatus.NO_ACTIVITY,
                Instant.now(clock));

        return DailyReportResponse.from(dailyReportRepository.saveAndFlush(report));
    }

    @Transactional
    public DailyReportResponse updateReport(UUID reportId, UpdateDailyReportRequest request) {
        DailyReport report = dailyReportRepository.findById(reportId)
                .orElseThrow(() -> new ResourceNotFoundException("Registro não encontrado."));

        report.updateContent(
                request.area().trim(),
                request.title().trim(),
                request.description().trim(),
                normalizeOptional(request.problems()),
                normalizeOptional(request.evidenceLinks()),
                normalizeOptional(request.participants()),
                normalizeOptional(request.environment()),
                normalizeOptional(request.recordType()),
                normalizeOptional(request.decisions()),
                normalizeOptional(request.testsAndObservations()),
                normalizeOptional(request.toolsUsed()),
                normalizeOptional(request.pendingItems()),
                normalizeOptional(request.finalNotes()));

        return DailyReportResponse.from(dailyReportRepository.saveAndFlush(report));
    }

    @Transactional
    public DailyReportResponse addAttachments(UUID reportId, List<MultipartFile> attachments) {
        DailyReport report = dailyReportRepository.findById(reportId)
                .orElseThrow(() -> new ResourceNotFoundException("Registro não encontrado."));

        int currentAttachments = report.getAttachments().size();
        int newAttachments = attachments == null ? 0 : (int) attachments.stream()
                .filter(file -> file != null && !file.isEmpty())
                .count();
        if (currentAttachments + newAttachments > 8) {
            throw new BusinessException("Cada registro pode ter no máximo 8 anexos.");
        }

        List<ReportAttachment> savedAttachments = attachmentService.storeAttachments(report, attachments);
        report.getAttachments().addAll(savedAttachments);
        return DailyReportResponse.from(report);
    }

    @Transactional
    public void deleteReport(UUID reportId) {
        DailyReport report = dailyReportRepository.findById(reportId)
                .orElseThrow(() -> new ResourceNotFoundException("Registro não encontrado."));

        dailyReportRepository.delete(report);
        dailyReportRepository.flush();
    }

    public List<MemberResponse> listPendingReports(LocalDate reportDate) {
        LocalDate selectedDate = reportDate == null ? LocalDate.now(clock) : reportDate;
        ensureDateIsNotFuture(selectedDate);
        Set<UUID> reportedMemberIds = dailyReportRepository.findAllByReportDateOrderBySubmittedAtDesc(selectedDate)
                .stream()
                .map(report -> report.getMember().getId())
                .collect(Collectors.toSet());

        return memberRepository.findAllByIsActiveTrueOrderByNameAsc()
                .stream()
                .filter(member -> !reportedMemberIds.contains(member.getId()))
                .map(MemberResponse::from)
                .toList();
    }

    public String exportMarkdown(LocalDate reportDate) {
        LocalDate selectedDate = reportDate == null ? LocalDate.now(clock) : reportDate;
        ensureDateIsNotFuture(selectedDate);
        List<DailyReport> reports = dailyReportRepository.findAllByReportDateOrderBySubmittedAtDesc(selectedDate)
                .stream()
                .sorted(Comparator.comparing(report -> report.getMember().getName()))
                .toList();
        List<DailyReport> activityReports = reports.stream()
                .filter(report -> report.getStatus() != ReportStatus.NO_ACTIVITY)
                .toList();
        List<DailyReport> noActivityReports = reports.stream()
                .filter(report -> report.getStatus() == ReportStatus.NO_ACTIVITY)
                .toList();
        List<MemberResponse> pendingMembers = listPendingReports(selectedDate);

        StringBuilder markdown = new StringBuilder();
        markdown.append("# Diário de Bordo — ").append(selectedDate).append("\n\n");
        markdown.append("## Resumo dos participantes\n\n");
        markdown.append("- Registros enviados: ").append(activityReports.size()).append("\n");
        markdown.append("- Sem atividade: ").append(noActivityReports.size()).append("\n");
        markdown.append("- Pendentes: ").append(pendingMembers.size()).append("\n\n");

        markdown.append("## Registros enviados\n\n");
        if (activityReports.isEmpty()) {
            markdown.append("Nenhum registro de atividade foi enviado para esta data.\n\n");
        } else {
            for (DailyReport report : activityReports) {
                appendActivityReport(markdown, report);
            }
        }

        markdown.append("## Próximo passo do Marco\n\n");
        markdown.append("Usar os registros acima como base para montar a entrada oficial do Diário de Bordo, com apoio de IA quando fizer sentido. Os próximos passos do projeto não são responsabilidade de quem preencheu o formulário; eles devem ser definidos pelo Marco a partir deste consolidado.\n\n");

        markdown.append("## Sem atividade\n\n");
        if (noActivityReports.isEmpty()) {
            markdown.append("Nenhum integrante marcou sem atividade nesta data.\n\n");
        } else {
            for (DailyReport report : noActivityReports) {
                markdown.append("- ").append(report.getMember().getName())
                        .append(" — selecionou que não trabalhou no projeto nesta data.")
                        .append("\n");
            }
            markdown.append("\n");
        }

        markdown.append("## Pendentes\n\n");
        if (pendingMembers.isEmpty()) {
            markdown.append("Nenhum integrante pendente nesta data.\n");
        } else {
            for (MemberResponse member : pendingMembers) {
                markdown.append("- ").append(member.name()).append("\n");
            }
        }

        return markdown.toString();
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

    private void ensureDateIsNotFuture(LocalDate reportDate) {
        if (reportDate != null && reportDate.isAfter(LocalDate.now(clock))) {
            throw new InvalidRequestException("Não é possível usar datas futuras no Diário de Bordo.");
        }
    }

    private void ensureEvidenceWasProvided(String evidenceLinks, List<MultipartFile> attachments) {
        boolean hasTextEvidence = evidenceLinks != null && !evidenceLinks.isBlank();
        boolean hasFileEvidence = attachments != null && attachments.stream()
                .anyMatch(file -> file != null && !file.isEmpty());
        if (!hasTextEvidence && !hasFileEvidence) {
            throw new InvalidRequestException("Adicione pelo menos um link, texto ou arquivo de evidência.");
        }
    }

    private ReportStatus deriveStatus(LocalDate reportDate) {
        return reportDate.isEqual(LocalDate.now(clock))
                ? ReportStatus.SUBMITTED
                : ReportStatus.SUBMITTED_LATE;
    }

    private void appendActivityReport(StringBuilder markdown, DailyReport report) {
        markdown.append("### ").append(report.getMember().getName()).append("\n\n");
        appendField(markdown, "Frente principal/área", report.getArea());
        appendField(markdown, "Enviado em", report.getSubmittedAt());
        appendField(markdown, "Participantes envolvidos", report.getParticipants());
        appendField(markdown, "Local/ambiente", report.getEnvironment());
        appendField(markdown, "Tipo de registro", report.getRecordType());
        appendField(markdown, "Objetivo do dia", report.getTitle());
        appendField(markdown, "O que foi feito", report.getDescription());
        appendField(markdown, "Status do dia", statusLabel(report.getStatus()));
        appendField(markdown, "Decisões tomadas", report.getDecisions());
        appendField(markdown, "Testes/observações/dados coletados", report.getTestsAndObservations());
        appendField(markdown, "Problemas/dificuldades/riscos", report.getProblems());
        appendField(markdown, "Evidências geradas", report.getEvidenceLinks());
        appendAttachments(markdown, report);
        appendField(markdown, "Uso de IA/ferramentas", report.getToolsUsed());
        appendField(markdown, "Pendências geradas", report.getPendingItems());
        appendField(markdown, "Observação final", report.getFinalNotes());
        markdown.append("\n");
    }

    private void appendAttachments(StringBuilder markdown, DailyReport report) {
        List<ReportAttachment> attachments = report.getAttachments();
        if (attachments == null || attachments.isEmpty()) {
            return;
        }

        markdown.append("- **Arquivos anexados:**\n");
        for (ReportAttachment attachment : attachments) {
            markdown.append("  - ")
                    .append("[")
                    .append(attachment.getOriginalFilename())
                    .append("](")
                    .append(publicBaseUrl)
                    .append("/reports/")
                    .append(report.getId())
                    .append("/attachments/")
                    .append(attachment.getId())
                    .append("/download?token=")
                    .append(attachment.getDownloadToken())
                    .append(")")
                    .append(" (")
                    .append(attachment.getCategory())
                    .append(", ")
                    .append(formatAttachmentSize(attachment.getSizeBytes()))
                    .append(")\n");
        }
    }

    private String formatAttachmentSize(long sizeBytes) {
        if (sizeBytes < 1024L * 1024L) {
            return Math.max(1, sizeBytes / 1024L) + " KB";
        }
        return String.format("%.1f MB", sizeBytes / 1024.0 / 1024.0).replace('.', ',');
    }

    private String statusLabel(ReportStatus status) {
        return switch (status) {
            case SUBMITTED -> "Enviado";
            case SUBMITTED_LATE -> "Enviado com atraso";
            case NO_ACTIVITY -> "Sem atividade";
        };
    }

    private void appendField(StringBuilder markdown, String label, Object value) {
        if (value == null) {
            return;
        }
        String text = value.toString().trim();
        if (text.isEmpty()) {
            return;
        }
        markdown.append("- **").append(label).append(":** ").append(text).append("\n");
    }

    private String normalizeOptional(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }
}
