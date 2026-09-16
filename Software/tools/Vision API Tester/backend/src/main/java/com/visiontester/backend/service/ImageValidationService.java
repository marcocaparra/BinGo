package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.ImageValidationResponse;
import com.visiontester.backend.api.dto.ProviderValidationResultResponse;
import com.visiontester.backend.api.dto.SaveImageValidationRequest;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.ImageValidation;
import com.visiontester.backend.domain.ImageValidationStatus;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.repository.ImageValidationRepository;
import com.visiontester.backend.repository.ProviderRunRepository;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ImageValidationService {

    private final ImageStorageService imageStorageService;
    private final ClassificationCategoryService classificationCategoryService;
    private final ImageValidationRepository imageValidationRepository;
    private final ProviderRunRepository providerRunRepository;
    private final DtoMapper mapper;

    public ImageValidationService(
            ImageStorageService imageStorageService,
            ClassificationCategoryService classificationCategoryService,
            ImageValidationRepository imageValidationRepository,
            ProviderRunRepository providerRunRepository,
            DtoMapper mapper
    ) {
        this.imageStorageService = imageStorageService;
        this.classificationCategoryService = classificationCategoryService;
        this.imageValidationRepository = imageValidationRepository;
        this.providerRunRepository = providerRunRepository;
        this.mapper = mapper;
    }

    @Transactional
    public ImageValidationResponse save(UUID imageId, SaveImageValidationRequest request) {
        validate(request);
        ImageAsset image = imageStorageService.getRequired(imageId);
        ClassificationCategory confirmedClass = request.humanConfirmedClassId() == null
                ? null
                : classificationCategoryService.getRequired(request.humanConfirmedClassId());
        ImageValidation validation = imageValidationRepository.findByImage_Id(imageId)
                .orElseGet(() -> new ImageValidation(image));
        validation.update(
                request.imageValidationStatus(),
                request.humanIsEwaste(),
                confirmedClass,
                request.humanNote()
        );
        imageValidationRepository.save(validation);

        List<ProviderRun> providerRuns = providerRunRepository.findByImage_Id(imageId);
        providerRuns.forEach(providerRun -> applyCorrectness(providerRun, validation));
        providerRunRepository.saveAll(providerRuns);

        return toResponse(validation, providerRuns, mapper);
    }

    private void validate(SaveImageValidationRequest request) {
        if (request.imageValidationStatus() == ImageValidationStatus.VALID && request.humanIsEwaste() == null) {
            throw new BadRequestException("humanIsEwaste is required for a valid image");
        }
        if (request.imageValidationStatus() == ImageValidationStatus.INVALID
                && (request.humanIsEwaste() != null || request.humanConfirmedClassId() != null)) {
            throw new BadRequestException("Invalid images cannot have e-waste or class truth");
        }
        if (Boolean.FALSE.equals(request.humanIsEwaste()) && request.humanConfirmedClassId() != null) {
            throw new BadRequestException("A non e-waste image cannot have an e-waste class");
        }
    }

    static void applyCorrectness(ProviderRun providerRun, ImageValidation validation) {
        if (validation.getValidationStatus() == ImageValidationStatus.INVALID) {
            providerRun.applyHumanValidation(null, null);
            return;
        }

        Boolean eligibilityCorrect = switch (providerRun.getEwasteEligibility()) {
            case ELIGIBLE -> Boolean.TRUE.equals(validation.getHumanIsEwaste());
            case NOT_ELIGIBLE -> Boolean.FALSE.equals(validation.getHumanIsEwaste());
            case REVIEW -> null;
        };
        Boolean classificationCorrect = validation.getHumanConfirmedClass() == null
                ? null
                : providerRun.getSuggestedClass() != null
                    && providerRun.getSuggestedClass().getId().equals(validation.getHumanConfirmedClass().getId());
        providerRun.applyHumanValidation(eligibilityCorrect, classificationCorrect);
    }

    static ImageValidationResponse toResponse(
            ImageValidation validation,
            List<ProviderRun> providerRuns,
            DtoMapper mapper
    ) {
        return new ImageValidationResponse(
                validation.getId(),
                validation.getImage().getId(),
                validation.getValidationStatus(),
                validation.getHumanIsEwaste(),
                mapper.toClassificationCategoryResponse(validation.getHumanConfirmedClass()),
                validation.getHumanNote(),
                validation.getValidatedAt(),
                providerRuns.stream()
                        .map(providerRun -> new ProviderValidationResultResponse(
                                providerRun.getId(),
                                providerRun.getProvider(),
                                providerRun.getEligibilityCorrect(),
                                providerRun.getClassificationCorrect()
                        ))
                        .toList()
        );
    }
}
