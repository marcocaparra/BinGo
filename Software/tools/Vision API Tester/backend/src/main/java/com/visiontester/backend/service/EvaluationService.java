package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.EvaluationResponse;
import com.visiontester.backend.api.dto.SaveEvaluationRequest;
import com.visiontester.backend.domain.HumanEvaluation;
import com.visiontester.backend.domain.ProviderRun;
import com.visiontester.backend.repository.HumanEvaluationRepository;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class EvaluationService {

    private final HumanEvaluationRepository humanEvaluationRepository;
    private final ProviderResultService providerResultService;
    private final ClassificationCategoryService classificationCategoryService;
    private final DtoMapper mapper;

    public EvaluationService(
            HumanEvaluationRepository humanEvaluationRepository,
            ProviderResultService providerResultService,
            ClassificationCategoryService classificationCategoryService,
            DtoMapper mapper
    ) {
        this.humanEvaluationRepository = humanEvaluationRepository;
        this.providerResultService = providerResultService;
        this.classificationCategoryService = classificationCategoryService;
        this.mapper = mapper;
    }

    @Transactional
    public EvaluationResponse save(UUID providerRunId, SaveEvaluationRequest request) {
        ProviderRun providerRun = providerResultService.getRequired(providerRunId);
        var correctClass = classificationCategoryService.getRequired(request.correctClassId());
        HumanEvaluation evaluation = humanEvaluationRepository.findByProviderRun(providerRun)
                .orElseGet(() -> new HumanEvaluation(
                        providerRun,
                        correctClass,
                        request.evaluationResult(),
                        request.targetObject(),
                        request.humanNote()
                ));

        evaluation.update(
                correctClass,
                request.evaluationResult(),
                request.targetObject(),
                request.humanNote()
        );

        return mapper.toEvaluationResponse(humanEvaluationRepository.save(evaluation));
    }
}
