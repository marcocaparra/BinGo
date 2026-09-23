package com.visiontester.backend.api;

import com.visiontester.backend.api.dto.AnalyzeImageRequest;
import com.visiontester.backend.api.dto.ImageResponse;
import com.visiontester.backend.api.dto.ProviderResultResponse;
import com.visiontester.backend.service.ImageStorageService;
import com.visiontester.backend.service.VisionAnalysisService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@Validated
@RestController
@RequestMapping("/api/images")
public class ImageController {

    private final ImageStorageService imageStorageService;
    private final VisionAnalysisService visionAnalysisService;

    public ImageController(ImageStorageService imageStorageService, VisionAnalysisService visionAnalysisService) {
        this.imageStorageService = imageStorageService;
        this.visionAnalysisService = visionAnalysisService;
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public ImageResponse upload(
            @RequestParam @NotNull UUID projectId,
            @RequestPart("file") MultipartFile file
    ) {
        return imageStorageService.upload(projectId, file);
    }

    @PostMapping("/{imageId}/analyze")
    @ResponseStatus(HttpStatus.CREATED)
    public List<ProviderResultResponse> analyze(
            @PathVariable UUID imageId,
            @Valid @RequestBody AnalyzeImageRequest request
    ) {
        return visionAnalysisService.analyze(imageId, request);
    }

    @DeleteMapping("/{imageId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID imageId) {
        imageStorageService.delete(imageId);
    }
}
