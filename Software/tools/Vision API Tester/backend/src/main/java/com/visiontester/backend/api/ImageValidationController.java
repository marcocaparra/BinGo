package com.visiontester.backend.api;

import com.visiontester.backend.api.dto.ImageValidationResponse;
import com.visiontester.backend.api.dto.SaveImageValidationRequest;
import com.visiontester.backend.service.ImageValidationService;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/images/{imageId}/validation")
public class ImageValidationController {

    private final ImageValidationService imageValidationService;

    public ImageValidationController(ImageValidationService imageValidationService) {
        this.imageValidationService = imageValidationService;
    }

    @PutMapping
    public ImageValidationResponse save(
            @PathVariable UUID imageId,
            @Valid @RequestBody SaveImageValidationRequest request
    ) {
        return imageValidationService.save(imageId, request);
    }
}
