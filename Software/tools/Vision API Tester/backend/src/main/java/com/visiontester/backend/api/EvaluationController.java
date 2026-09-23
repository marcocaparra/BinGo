package com.visiontester.backend.api;

import com.visiontester.backend.api.dto.EvaluationResponse;
import com.visiontester.backend.api.dto.SaveEvaluationRequest;
import com.visiontester.backend.service.EvaluationService;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/provider-results/{providerRunId}/evaluation")
public class EvaluationController {

    private final EvaluationService evaluationService;

    public EvaluationController(EvaluationService evaluationService) {
        this.evaluationService = evaluationService;
    }

    @PutMapping
    public EvaluationResponse save(
            @PathVariable UUID providerRunId,
            @Valid @RequestBody SaveEvaluationRequest request
    ) {
        return evaluationService.save(providerRunId, request);
    }
}
