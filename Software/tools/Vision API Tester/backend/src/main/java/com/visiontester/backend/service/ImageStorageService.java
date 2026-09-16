package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.ImageResponse;
import com.visiontester.backend.config.StorageProperties;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.Project;
import com.visiontester.backend.repository.ImageAssetRepository;
import java.awt.image.BufferedImage;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.Locale;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
public class ImageStorageService {

    private final StorageProperties storageProperties;
    private final ProjectService projectService;
    private final ImageAssetRepository imageAssetRepository;
    private final DtoMapper mapper;

    public ImageStorageService(
            StorageProperties storageProperties,
            ProjectService projectService,
            ImageAssetRepository imageAssetRepository,
            DtoMapper mapper
    ) {
        this.storageProperties = storageProperties;
        this.projectService = projectService;
        this.imageAssetRepository = imageAssetRepository;
        this.mapper = mapper;
    }

    @Transactional
    public ImageResponse upload(UUID projectId, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BadRequestException("Image file is required");
        }

        String contentType = file.getContentType();
        if (contentType == null || !contentType.toLowerCase(Locale.ROOT).startsWith("image/")) {
            throw new BadRequestException("Only image uploads are accepted");
        }

        Project project = projectService.getRequired(projectId);
        StoredImage storedImage = storeFile(file);
        ImageDimensions dimensions = readDimensions(storedImage.path());

        ImageAsset image = imageAssetRepository.save(new ImageAsset(
                project,
                originalFilename(file),
                storedImage.path().getFileName().toString(),
                storedImage.path().toString(),
                contentType,
                file.getSize(),
                storedImage.sha256(),
                dimensions.width(),
                dimensions.height()
        ));

        return mapper.toImageResponse(image);
    }

    @Transactional(readOnly = true)
    public ImageAsset getRequired(UUID imageId) {
        return imageAssetRepository.findById(imageId)
                .orElseThrow(() -> new ResourceNotFoundException("Image not found"));
    }

    @Transactional
    public void delete(UUID imageId) {
        ImageAsset image = getRequired(imageId);
        Path storagePath = Path.of(image.getStoragePath());

        imageAssetRepository.delete(image);

        try {
            Files.deleteIfExists(storagePath);
        } catch (Exception exception) {
            throw new BadRequestException("Image metadata was not deleted because the file could not be removed: " + exception.getMessage());
        }
    }

    private StoredImage storeFile(MultipartFile file) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            LocalDate today = LocalDate.now();
            Path directory = Path.of(
                    storageProperties.getRootPath(),
                    String.valueOf(today.getYear()),
                    String.format("%02d", today.getMonthValue())
            ).toAbsolutePath().normalize();
            Files.createDirectories(directory);

            String storedFilename = UUID.randomUUID() + extensionOf(originalFilename(file));
            Path target = directory.resolve(storedFilename).normalize();

            try (InputStream inputStream = file.getInputStream();
                 DigestInputStream digestInputStream = new DigestInputStream(inputStream, digest)) {
                Files.copy(digestInputStream, target);
            }

            return new StoredImage(target, HexFormat.of().formatHex(digest.digest()));
        } catch (Exception exception) {
            throw new BadRequestException("Could not store image: " + exception.getMessage());
        }
    }

    private ImageDimensions readDimensions(Path path) {
        try (InputStream inputStream = Files.newInputStream(path)) {
            BufferedImage image = ImageIO.read(inputStream);
            if (image == null) {
                return new ImageDimensions(null, null);
            }
            return new ImageDimensions(image.getWidth(), image.getHeight());
        } catch (Exception exception) {
            return new ImageDimensions(null, null);
        }
    }

    private String originalFilename(MultipartFile file) {
        String originalFilename = file.getOriginalFilename();
        if (originalFilename == null || originalFilename.isBlank()) {
            return "uploaded-image";
        }
        return Path.of(originalFilename).getFileName().toString();
    }

    private String extensionOf(String filename) {
        int index = filename.lastIndexOf('.');
        if (index < 0 || index == filename.length() - 1) {
            return "";
        }
        return filename.substring(index).toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9.]", "");
    }

    private record StoredImage(Path path, String sha256) {
    }

    private record ImageDimensions(Integer width, Integer height) {
    }
}
