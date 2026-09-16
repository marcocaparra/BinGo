package com.visiontester.backend.api.dto;

public record DashboardAlertResponse(
        String severity,
        String title,
        String message
) {
}
