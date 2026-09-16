package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.ProviderResultResponse;
import com.visiontester.backend.api.dto.SaveProviderResultRequest;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.ProviderLabel;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.domain.ProviderRunStatus;
import com.visiontester.backend.repository.ProviderRunRepository;
import com.visiontester.backend.repository.ImageValidationRepository;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;

@Service
public class ProviderResultService {

    private final ProviderRunRepository providerRunRepository;
    private final ImageValidationRepository imageValidationRepository;
    private final ImageStorageService imageStorageService;
    private final ClassificationSuggestionService classificationSuggestionService;
    private final EwasteEligibilityPolicy ewasteEligibilityPolicy;
    private final ObjectMapper objectMapper;
    private final DtoMapper mapper;

    public ProviderResultService(
            ProviderRunRepository providerRunRepository,
            ImageValidationRepository imageValidationRepository,
            ImageStorageService imageStorageService,
            ClassificationSuggestionService classificationSuggestionService,
            EwasteEligibilityPolicy ewasteEligibilityPolicy,
            ObjectMapper objectMapper,
            DtoMapper mapper
    ) {
        this.providerRunRepository = providerRunRepository;
        this.imageValidationRepository = imageValidationRepository;
        this.imageStorageService = imageStorageService;
        this.classificationSuggestionService = classificationSuggestionService;
        this.ewasteEligibilityPolicy = ewasteEligibilityPolicy;
        this.objectMapper = objectMapper;
        this.mapper = mapper;
    }

    @Transactional
    public ProviderResultResponse save(SaveProviderResultRequest request) {
        return save(request, ProviderRunStatus.MANUAL);
    }

    @Transactional
    public ProviderResultResponse save(SaveProviderResultRequest request, ProviderRunStatus status) {
        ImageAsset image = imageStorageService.getRequired(request.imageId());
        var rawResponse = request.rawResponse() == null || request.rawResponse().isNull()
                ? objectMapper.createObjectNode()
                : request.rawResponse();

        ProviderRun providerRun = new ProviderRun(
                image,
                request.provider().trim(),
                status,
                request.responseTimeMs(),
                rawResponse
        );

        if (request.labels() != null) {
            request.labels().forEach(label ->
                    providerRun.addLabel(new ProviderLabel(label.name().trim(), label.confidence()))
            );
        }

        ClassificationDecision classification = classificationSuggestionService.classify(providerRun.getLabels());
        var ewasteEligibility = ewasteEligibilityPolicy.derive(classification);
        providerRun.applyClassification(
                classification.suggestedClass(),
                classification.status(),
                classification.score(),
                classification.margin(),
                classification.engineVersion(),
                objectMapper.valueToTree(classification.evidence()),
                ewasteEligibility
        );
        imageValidationRepository.findByImage_Id(image.getId())
                .ifPresent(validation -> ImageValidationService.applyCorrectness(providerRun, validation));

        return mapper.toProviderResultResponse(providerRunRepository.save(providerRun));
    }

    @Transactional(readOnly = true)
    public ProviderRun getRequired(UUID providerRunId) {
        return providerRunRepository.findById(providerRunId)
                .orElseThrow(() -> new ResourceNotFoundException("Provider result not found"));
    }

    @Transactional(readOnly = true)
    public List<ProviderResultResponse> listByImage(UUID imageId) {
        return providerRunRepository.findByImage_Id(imageId).stream()
                .map(mapper::toProviderResultResponse)
                .toList();
    }

}
