package com.visiontester.backend.api;

import com.visiontester.backend.api.dto.DashboardMetricsResponse;
import com.visiontester.backend.service.DashboardService;
import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/dashboard")
public class DashboardController {

    private final DashboardService dashboardService;

    public DashboardController(DashboardService dashboardService) {
        this.dashboardService = dashboardService;
    }

    @GetMapping
    public DashboardMetricsResponse metrics(@RequestParam(required = false) UUID projectId) {
        return dashboardService.metrics(projectId);
    }
}
