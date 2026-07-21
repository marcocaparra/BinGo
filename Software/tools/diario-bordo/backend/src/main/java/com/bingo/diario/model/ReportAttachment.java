package com.bingo.diario.model;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

import org.hibernate.annotations.CreationTimestamp;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "diary_report_attachments")
public class ReportAttachment {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "report_id", nullable = false)
    private DailyReport report;

    @Column(name = "original_filename", nullable = false, length = 255)
    private String originalFilename;

    @Column(name = "stored_filename", nullable = false, length = 255)
    private String storedFilename;

    @Column(name = "content_type", nullable = false, length = 120)
    private String contentType;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(nullable = false, length = 40)
    private String category;

    @Column(name = "storage_path", nullable = false, length = 600)
    private String storagePath;

    @Column(name = "download_token", nullable = false, length = 80)
    private String downloadToken;

    @CreationTimestamp
    @Column(name = "uploaded_at", nullable = false, updatable = false)
    private Instant uploadedAt;

    protected ReportAttachment() {
    }

    public ReportAttachment(
            DailyReport report,
            String originalFilename,
            String storedFilename,
            String contentType,
            long sizeBytes,
            String category,
            String storagePath) {
        this.report = report;
        this.originalFilename = originalFilename;
        this.storedFilename = storedFilename;
        this.contentType = contentType;
        this.sizeBytes = sizeBytes;
        this.category = category;
        this.storagePath = storagePath;
        this.downloadToken = UUID.randomUUID().toString();
    }

    public UUID getId() {
        return id;
    }

    public DailyReport getReport() {
        return report;
    }

    public String getOriginalFilename() {
        return originalFilename;
    }

    public String getStoredFilename() {
        return storedFilename;
    }

    public String getContentType() {
        return contentType;
    }

    public long getSizeBytes() {
        return sizeBytes;
    }

    public String getCategory() {
        return category;
    }

    public String getStoragePath() {
        return storagePath;
    }

    public String getDownloadToken() {
        return Objects.requireNonNullElseGet(downloadToken, () -> id == null ? "" : id.toString());
    }

    public Instant getUploadedAt() {
        return uploadedAt;
    }
}
