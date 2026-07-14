package com.bingo.diario.controller;

import java.time.Clock;
import java.time.LocalDate;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;

import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.bingo.diario.dto.CreateNoActivityReportRequest;
import com.bingo.diario.dto.CreateTodayReportRequest;
import com.bingo.diario.dto.DailyReportResponse;
import com.bingo.diario.dto.MemberResponse;
import com.bingo.diario.dto.ReportExistenceResponse;
import com.bingo.diario.dto.UpdateDailyReportRequest;
import com.bingo.diario.model.ReportAttachment;
import com.bingo.diario.service.AuthService;
import com.bingo.diario.service.DailyReportService;
import com.bingo.diario.service.ReportAttachmentService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/reports")
public class DailyReportController {

    private final DailyReportService dailyReportService;
    private final ReportAttachmentService attachmentService;
    private final AuthService authService;
    private final Clock clock;

    public DailyReportController(
            DailyReportService dailyReportService,
            ReportAttachmentService attachmentService,
            AuthService authService,
            Clock clock) {
        this.dailyReportService = dailyReportService;
        this.attachmentService = attachmentService;
        this.authService = authService;
        this.clock = clock;
    }

    @GetMapping
    public List<DailyReportResponse> listReports(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @RequestParam(required = false) LocalDate date) {
        authService.requireAdminAccess(password);
        return dailyReportService.listReports(date);
    }

    @PostMapping(value = "/today", consumes = MediaType.APPLICATION_JSON_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public DailyReportResponse createTodayReport(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @Valid @RequestBody CreateTodayReportRequest request) {
        authService.requireTeamAccess(password);
        return dailyReportService.createTodayReport(request);
    }

    @PostMapping(value = "/today", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public DailyReportResponse createTodayReportWithAttachments(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @Valid @RequestPart("report") CreateTodayReportRequest request,
            @RequestPart(value = "files", required = false) List<MultipartFile> files) {
        authService.requireTeamAccess(password);
        return dailyReportService.createTodayReport(request, files);
    }

    @GetMapping("/exists")
    public ReportExistenceResponse checkReportExists(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @RequestParam UUID memberId,
            @RequestParam LocalDate date) {
        authService.requireTeamAccess(password);
        return dailyReportService.checkReportExists(memberId, date);
    }

    @PutMapping("/{id}")
    public DailyReportResponse updateReport(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @PathVariable UUID id,
            @Valid @RequestBody UpdateDailyReportRequest request) {
        authService.requireAdminAccess(password);
        return dailyReportService.updateReport(id, request);
    }

    @PostMapping(value = "/{id}/attachments", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public DailyReportResponse addAttachments(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @PathVariable UUID id,
            @RequestPart(value = "files", required = false) List<MultipartFile> files) {
        authService.requireAdminAccess(password);
        return dailyReportService.addAttachments(id, files);
    }

    @GetMapping("/{reportId}/attachments/{attachmentId}/download")
    public ResponseEntity<Resource> downloadAttachment(
            @PathVariable UUID reportId,
            @PathVariable UUID attachmentId,
            @RequestParam String token) {
        ReportAttachment attachment = attachmentService.findDownloadableAttachment(reportId, attachmentId, token);
        Resource resource = attachmentService.loadAttachmentResource(attachment);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(attachment.getContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                        .filename(attachment.getOriginalFilename(), StandardCharsets.UTF_8)
                        .build()
                        .toString())
                .body(resource);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteReport(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @PathVariable UUID id) {
        authService.requireAdminAccess(password);
        dailyReportService.deleteReport(id);
    }

    @PostMapping("/no-activity")
    @ResponseStatus(HttpStatus.CREATED)
    public DailyReportResponse createNoActivityReport(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @Valid @RequestBody CreateNoActivityReportRequest request) {
        authService.requireTeamAccess(password);
        return dailyReportService.createNoActivityReport(request);
    }

    @GetMapping("/pending")
    public List<MemberResponse> listPendingReports(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @RequestParam(required = false) LocalDate date) {
        authService.requireAdminAccess(password);
        return dailyReportService.listPendingReports(date);
    }

    @GetMapping(value = "/export", produces = "text/markdown;charset=UTF-8")
    public ResponseEntity<String> exportReports(
            @RequestHeader(value = AuthService.PASSWORD_HEADER, required = false) String password,
            @RequestParam(required = false) LocalDate date) {
        authService.requireAdminAccess(password);
        LocalDate selectedDate = date == null ? LocalDate.now(clock) : date;
        String filename = "diario-bordo-" + selectedDate + ".md";
        return ResponseEntity.ok()
                .contentType(MediaType.valueOf("text/markdown;charset=UTF-8"))
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                        .filename(filename)
                        .build()
                        .toString())
                .body(dailyReportService.exportMarkdown(selectedDate));
    }
}
