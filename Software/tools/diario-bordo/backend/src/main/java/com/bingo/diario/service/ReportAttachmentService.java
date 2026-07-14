package com.bingo.diario.service;

import java.io.IOException;
import java.net.MalformedURLException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.Normalizer;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import com.bingo.diario.exception.InvalidRequestException;
import com.bingo.diario.exception.ResourceNotFoundException;
import com.bingo.diario.model.DailyReport;
import com.bingo.diario.model.ReportAttachment;
import com.bingo.diario.repository.ReportAttachmentRepository;

@Service
public class ReportAttachmentService {

    private static final int MAX_FILES_PER_REPORT = 8;
    private static final long MAX_IMAGE_BYTES = 10L * 1024L * 1024L;
    private static final long MAX_DOCUMENT_BYTES = 25L * 1024L * 1024L;
    private static final long MAX_VIDEO_BYTES = 64L * 1024L * 1024L;
    private static final long MAX_TOTAL_BYTES = 96L * 1024L * 1024L;

    private static final Set<String> IMAGE_EXTENSIONS = Set.of("jpg", "jpeg", "png", "webp", "gif");
    private static final Set<String> VIDEO_EXTENSIONS = Set.of("mp4", "mov", "webm");
    private static final Set<String> DOCUMENT_EXTENSIONS = Set.of(
            "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "md", "csv", "dxf");

    private final ReportAttachmentRepository attachmentRepository;
    private final Path storageRoot;

    public ReportAttachmentService(
            ReportAttachmentRepository attachmentRepository,
            @Value("${app.attachments.storage-path:uploads/diario-bordo}") String storagePath) {
        this.attachmentRepository = attachmentRepository;
        this.storageRoot = Path.of(storagePath).toAbsolutePath().normalize();
    }

    public List<ReportAttachment> storeAttachments(DailyReport report, List<MultipartFile> files) {
        if (files == null || files.isEmpty()) {
            return List.of();
        }

        List<MultipartFile> usableFiles = files.stream()
                .filter(file -> file != null && !file.isEmpty())
                .toList();
        if (usableFiles.isEmpty()) {
            return List.of();
        }
        if (usableFiles.size() > MAX_FILES_PER_REPORT) {
            throw new InvalidRequestException("Envie no máximo " + MAX_FILES_PER_REPORT + " arquivos por registro.");
        }

        long totalBytes = usableFiles.stream().mapToLong(MultipartFile::getSize).sum();
        if (totalBytes > MAX_TOTAL_BYTES) {
            throw new InvalidRequestException("Os anexos do registro podem somar no máximo 96 MB.");
        }

        Path reportDirectory = storageRoot.resolve(report.getId().toString()).normalize();
        ensureInsideStorageRoot(reportDirectory);

        try {
            Files.createDirectories(reportDirectory);
        } catch (IOException exception) {
            throw new InvalidRequestException("Não foi possível preparar a pasta de anexos.");
        }

        Set<String> usedNames = new HashSet<>();
        List<ReportAttachment> attachments = usableFiles.stream()
                .map(file -> storeSingleFile(report, file, reportDirectory, usedNames))
                .toList();

        return attachmentRepository.saveAll(attachments);
    }

    public List<ReportAttachment> listByReportId(UUID reportId) {
        return attachmentRepository.findAllByReport_IdOrderByUploadedAtAsc(reportId);
    }

    public ReportAttachment findDownloadableAttachment(UUID reportId, UUID attachmentId, String token) {
        ReportAttachment attachment = attachmentRepository.findByIdAndReport_Id(attachmentId, reportId)
                .orElseThrow(() -> new ResourceNotFoundException("Anexo não encontrado."));
        if (token == null || token.isBlank() || !attachment.getDownloadToken().equals(token)) {
            throw new ResourceNotFoundException("Anexo não encontrado.");
        }
        return attachment;
    }

    public Resource loadAttachmentResource(ReportAttachment attachment) {
        Path filePath = storageRoot.resolve(attachment.getStoragePath()).normalize();
        ensureInsideStorageRoot(filePath);

        try {
            Resource resource = new UrlResource(filePath.toUri());
            if (!resource.exists() || !resource.isReadable()) {
                throw new ResourceNotFoundException("Arquivo anexado não encontrado.");
            }
            return resource;
        } catch (MalformedURLException exception) {
            throw new ResourceNotFoundException("Arquivo anexado não encontrado.");
        }
    }

    private ReportAttachment storeSingleFile(
            DailyReport report,
            MultipartFile file,
            Path reportDirectory,
            Set<String> usedNames) {
        String originalFilename = sanitizeFilename(file.getOriginalFilename());
        String extension = extensionOf(originalFilename);
        String category = categoryFor(extension);
        long maxSize = maxSizeFor(category);

        if (file.getSize() > maxSize) {
            throw new InvalidRequestException(originalFilename + " excede o limite de " + formatBytes(maxSize) + ".");
        }

        String storedFilename = uniqueStoredFilename(extension, usedNames);
        Path destination = reportDirectory.resolve(storedFilename).normalize();
        ensureInsideStorageRoot(destination);

        try {
            file.transferTo(destination);
        } catch (IOException exception) {
            throw new InvalidRequestException("Não foi possível salvar o anexo " + originalFilename + ".");
        }

        return new ReportAttachment(
                report,
                originalFilename,
                storedFilename,
                normalizedContentType(file.getContentType(), extension),
                file.getSize(),
                category,
                storageRoot.relativize(destination).toString().replace('\\', '/'));
    }

    private void ensureInsideStorageRoot(Path path) {
        if (!path.toAbsolutePath().normalize().startsWith(storageRoot)) {
            throw new InvalidRequestException("Caminho de anexo inválido.");
        }
    }

    private String sanitizeFilename(String filename) {
        String cleanName = StringUtils.cleanPath(filename == null ? "evidencia" : filename);
        cleanName = cleanName.replace('\\', '/');
        cleanName = cleanName.substring(cleanName.lastIndexOf('/') + 1);
        cleanName = Normalizer.normalize(cleanName, Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .replaceAll("[^A-Za-z0-9._ -]", "")
                .trim();

        if (cleanName.isBlank() || cleanName.equals(".") || cleanName.equals("..")) {
            return "evidencia";
        }

        return cleanName.length() > 180 ? cleanName.substring(cleanName.length() - 180) : cleanName;
    }

    private String extensionOf(String filename) {
        int dotIndex = filename.lastIndexOf('.');
        if (dotIndex < 0 || dotIndex == filename.length() - 1) {
            throw new InvalidRequestException(filename + " precisa ter uma extensão de arquivo.");
        }

        String extension = filename.substring(dotIndex + 1).toLowerCase(Locale.ROOT);
        if (!IMAGE_EXTENSIONS.contains(extension)
                && !VIDEO_EXTENSIONS.contains(extension)
                && !DOCUMENT_EXTENSIONS.contains(extension)) {
            throw new InvalidRequestException("Formato ." + extension + " não permitido nas evidências.");
        }

        return extension;
    }

    private String categoryFor(String extension) {
        if (IMAGE_EXTENSIONS.contains(extension)) {
            return "imagem";
        }
        if (VIDEO_EXTENSIONS.contains(extension)) {
            return "video";
        }
        return "documento";
    }

    private long maxSizeFor(String category) {
        return switch (category) {
            case "imagem" -> MAX_IMAGE_BYTES;
            case "video" -> MAX_VIDEO_BYTES;
            default -> MAX_DOCUMENT_BYTES;
        };
    }

    private String uniqueStoredFilename(String extension, Set<String> usedNames) {
        String filename;
        do {
            filename = UUID.randomUUID() + "." + extension;
        } while (!usedNames.add(filename));
        return filename;
    }

    private String normalizedContentType(String contentType, String extension) {
        if (contentType != null && !contentType.isBlank()) {
            return contentType;
        }
        return switch (extension) {
            case "jpg", "jpeg" -> "image/jpeg";
            case "png" -> "image/png";
            case "webp" -> "image/webp";
            case "gif" -> "image/gif";
            case "mp4" -> "video/mp4";
            case "mov" -> "video/quicktime";
            case "webm" -> "video/webm";
            case "pdf" -> "application/pdf";
            case "doc" -> "application/msword";
            case "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
            case "dxf" -> "image/vnd.dxf";
            default -> "application/octet-stream";
        };
    }

    private String formatBytes(long bytes) {
        return (bytes / 1024 / 1024) + " MB";
    }
}
