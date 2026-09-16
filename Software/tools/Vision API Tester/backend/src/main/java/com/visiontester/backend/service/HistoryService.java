package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.EvaluationResponse;
import com.visiontester.backend.api.dto.HistoryItemResponse;
import com.visiontester.backend.api.dto.HistoryProviderResponse;
import com.visiontester.backend.api.dto.ProviderLabelResponse;
import com.visiontester.backend.domain.HumanEvaluation;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.repository.HumanEvaluationRepository;
import com.visiontester.backend.repository.ImageAssetRepository;
import com.visiontester.backend.repository.ImageValidationRepository;
import com.visiontester.backend.repository.ProviderRunRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class HistoryService {

    private final ImageAssetRepository imageAssetRepository;
    private final ProviderRunRepository providerRunRepository;
    private final HumanEvaluationRepository humanEvaluationRepository;
    private final ImageValidationRepository imageValidationRepository;
    private final DtoMapper mapper;

    public HistoryService(
            ImageAssetRepository imageAssetRepository,
            ProviderRunRepository providerRunRepository,
            HumanEvaluationRepository humanEvaluationRepository,
            ImageValidationRepository imageValidationRepository,
            DtoMapper mapper
    ) {
        this.imageAssetRepository = imageAssetRepository;
        this.providerRunRepository = providerRunRepository;
        this.humanEvaluationRepository = humanEvaluationRepository;
        this.imageValidationRepository = imageValidationRepository;
        this.mapper = mapper;
    }

    @Transactional(readOnly = true)
    public List<HistoryItemResponse> list(UUID projectId) {
        List<ImageAsset> images = projectId == null
                ? imageAssetRepository.findTop50ByOrderByCreatedAtDesc()
                : imageAssetRepository.findTop50ByProject_IdOrderByCreatedAtDesc(projectId);

        return images.stream().map(this::toHistoryItem).toList();
    }

    @Transactional(readOnly = true)
    public HistoryItemResponse get(UUID imageId) {
        ImageAsset image = imageAssetRepository.findById(imageId)
                .orElseThrow(() -> new ResourceNotFoundException("Image not found"));
        return toHistoryItem(image);
    }

    private HistoryItemResponse toHistoryItem(ImageAsset image) {
        List<ProviderRun> providerRuns = providerRunRepository.findByImage_Id(image.getId());
        List<HistoryProviderResponse> providerResults = providerRuns.stream()
                .map(this::toHistoryProvider)
                .toList();

        return new HistoryItemResponse(
                image.getId(),
                image.getOriginalFilename(),
                image.getCreatedAt(),
                image.getProject().getId(),
                image.getProject().getName(),
                imageValidationRepository.findByImage_Id(image.getId())
                        .map(validation -> ImageValidationService.toResponse(validation, providerRuns, mapper))
                        .orElse(null),
                providerResults
        );
    }

    private HistoryProviderResponse toHistoryProvider(ProviderRun providerRun) {
        List<ProviderLabelResponse> labels = providerRun.getLabels().stream()
                .map(label -> new ProviderLabelResponse(label.getId(), label.getLabelName(), label.getConfidence()))
                .toList();
        Optional<HumanEvaluation> evaluation = humanEvaluationRepository.findByProviderRun_Id(providerRun.getId());

        return new HistoryProviderResponse(
                providerRun.getId(),
                providerRun.getProvider(),
                providerRun.getStatus().name(),
                providerRun.getResponseTimeMs(),
                labels,
                mapper.toClassificationCategoryResponse(providerRun.getSuggestedClass()),
                providerRun.getClassificationStatus() == null ? null : providerRun.getClassificationStatus().name(),
                providerRun.getClassificationScore(),
                providerRun.getClassificationMargin(),
                providerRun.getClassificationEngineVersion(),
                providerRun.getClassificationEvidence(),
                mapper.toEwasteEligibility(providerRun),
                providerRun.getEligibilityCorrect(),
                providerRun.getClassificationCorrect(),
                providerRun.getRawResponse(),
                evaluation.map(mapper::toEvaluationResponse).orElse(null),
                providerRun.getCreatedAt()
        );
    }
}
