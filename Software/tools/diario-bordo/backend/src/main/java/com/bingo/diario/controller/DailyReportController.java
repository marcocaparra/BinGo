package com.bingo.diario.controller;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.bingo.diario.dto.CreateNoActivityReportRequest;
import com.bingo.diario.dto.CreateTodayReportRequest;
import com.bingo.diario.dto.DailyReportResponse;
import com.bingo.diario.service.DailyReportService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/reports")
public class DailyReportController {

    private final DailyReportService dailyReportService;

    public DailyReportController(DailyReportService dailyReportService) {
        this.dailyReportService = dailyReportService;
    }

    @GetMapping
    public List<DailyReportResponse> listReports() {
        return dailyReportService.listReports();
    }

    @PostMapping("/today")
    @ResponseStatus(HttpStatus.CREATED)
    public DailyReportResponse createTodayReport(
            @Valid @RequestBody CreateTodayReportRequest request) {
        return dailyReportService.createTodayReport(request);
    }

    @PostMapping("/no-activity")
    @ResponseStatus(HttpStatus.CREATED)
    public DailyReportResponse createNoActivityReport(
            @Valid @RequestBody CreateNoActivityReportRequest request) {
        return dailyReportService.createNoActivityReport(request);
    }
}
