package com.visiontester.backend.api.dto;

import java.time.OffsetDateTime;
import java.util.UUID;

public record ImageResponse(
        UUID id,
        UUID projectId,
        String originalFilename,
        String storedFilename,
        String storagePath,
        String contentType,
        long sizeBytes,
        String checksumSha256,
        Integer width,
        Integer height,
        OffsetDateTime createdAt
) {
}
