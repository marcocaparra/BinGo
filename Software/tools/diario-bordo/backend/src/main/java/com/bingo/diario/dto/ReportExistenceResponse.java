package com.bingo.diario.dto;

import java.time.LocalDate;
import java.util.UUID;

public record ReportExistenceResponse(
        boolean exists,
        UUID reportId,
        UUID memberId,
        String memberName,
        LocalDate reportDate) {

    public static ReportExistenceResponse empty(UUID memberId, LocalDate reportDate) {
        return new ReportExistenceResponse(false, null, memberId, null, reportDate);
    }
}
