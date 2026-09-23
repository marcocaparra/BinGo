package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.EvaluationResponse;
import com.visiontester.backend.api.dto.ImageResponse;
import com.visiontester.backend.api.dto.ProjectResponse;
import com.visiontester.backend.api.dto.ProviderLabelResponse;
import com.visiontester.backend.api.dto.ProviderResultResponse;
import com.visiontester.backend.api.dto.ClassificationCategoryResponse;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationAlias;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.domain.HumanEvaluation;
import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.Project;
import com.visiontester.backend.domain.ProviderRun;
import java.util.List;
import org.springframework.stereotype.Component;

@Component
public class DtoMapper {

    public ProjectResponse toProjectResponse(Project project) {
        return new ProjectResponse(project.getId(), project.getName(), project.getDescription(), project.getCreatedAt());
    }

    public ImageResponse toImageResponse(ImageAsset image) {
        return new ImageResponse(
                image.getId(),
                image.getProject().getId(),
                image.getOriginalFilename(),
                image.getStoredFilename(),
                image.getStoragePath(),
                image.getContentType(),
                image.getSizeBytes(),
                image.getChecksumSha256(),
                image.getWidth(),
                image.getHeight(),
                image.getCreatedAt()
        );
    }

    public ProviderResultResponse toProviderResultResponse(ProviderRun providerRun) {
        List<ProviderLabelResponse> labels = providerRun.getLabels().stream()
                .map(label -> new ProviderLabelResponse(label.getId(), label.getLabelName(), label.getConfidence()))
                .toList();
        return new ProviderResultResponse(
                providerRun.getId(),
                providerRun.getImage().getId(),
                providerRun.getProvider(),
                providerRun.getStatus().name(),
                providerRun.getResponseTimeMs(),
                labels,
                toClassificationCategoryResponse(providerRun.getSuggestedClass()),
                providerRun.getClassificationStatus() == null ? null : providerRun.getClassificationStatus().name(),
                providerRun.getClassificationScore(),
                providerRun.getClassificationMargin(),
                providerRun.getClassificationEngineVersion(),
                providerRun.getClassificationEvidence(),
                toEwasteEligibility(providerRun),
                providerRun.getEligibilityCorrect(),
                providerRun.getClassificationCorrect(),
                providerRun.getRawResponse(),
                providerRun.getCreatedAt()
        );
    }

    public EvaluationResponse toEvaluationResponse(HumanEvaluation evaluation) {
        return new EvaluationResponse(
                evaluation.getId(),
                evaluation.getProviderRun().getId(),
                evaluation.getCorrectClass().getId(),
                evaluation.getCorrectClass().getCode(),
                evaluation.getCorrectClass().getName(),
                evaluation.getEvaluationResult(),
                evaluation.isTargetObject(),
                evaluation.getHumanNote(),
                evaluation.getEvaluatedAt()
        );
    }

    public ClassificationCategoryResponse toClassificationCategoryResponse(ClassificationCategory category) {
        if (category == null) {
            return null;
        }

        return new ClassificationCategoryResponse(
                category.getId(),
                category.getCode(),
                category.getName(),
                category.getAliases().stream()
                        .map(ClassificationAlias::getAlias)
                        .sorted(String.CASE_INSENSITIVE_ORDER)
                        .toList(),
                category.getCategoryType(),
                category.getDefaultEwasteEligibility(),
                category.getDisplayOrder(),
                category.isActive()
        );
    }

    public EwasteEligibility toEwasteEligibility(ProviderRun providerRun) {
        return providerRun.getEwasteEligibility();
    }

}
