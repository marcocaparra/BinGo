package com.bingo.diario.dto;

import java.time.Instant;
import java.util.UUID;

import com.bingo.diario.model.ReportAttachment;

public record ReportAttachmentResponse(
        UUID id,
        String originalFilename,
        String contentType,
        long sizeBytes,
        String category,
        String downloadUrl,
        Instant uploadedAt) {

    public static ReportAttachmentResponse from(ReportAttachment attachment) {
        return new ReportAttachmentResponse(
                attachment.getId(),
                attachment.getOriginalFilename(),
                attachment.getContentType(),
                attachment.getSizeBytes(),
                attachment.getCategory(),
                "/reports/" + attachment.getReport().getId()
                        + "/attachments/" + attachment.getId()
                        + "/download?token=" + attachment.getDownloadToken(),
                attachment.getUploadedAt());
    }
}
