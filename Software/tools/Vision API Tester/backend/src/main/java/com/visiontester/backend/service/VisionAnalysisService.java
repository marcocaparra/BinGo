package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.AnalyzeImageRequest;
import com.visiontester.backend.api.dto.ProviderLabelRequest;
import com.visiontester.backend.api.dto.ProviderResultResponse;
import com.visiontester.backend.api.dto.SaveProviderResultRequest;
import com.visiontester.backend.domain.ProviderRunStatus;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Service
public class VisionAnalysisService {

    private final ProviderResultService providerResultService;
    private final ImageStorageService imageStorageService;
    private final AwsRekognitionProviderClient awsRekognitionProviderClient;
    private final GoogleCloudVisionProviderClient googleCloudVisionProviderClient;
    private final ObjectMapper objectMapper;

    public VisionAnalysisService(
            ProviderResultService providerResultService,
            ImageStorageService imageStorageService,
            AwsRekognitionProviderClient awsRekognitionProviderClient,
            GoogleCloudVisionProviderClient googleCloudVisionProviderClient,
            ObjectMapper objectMapper
    ) {
        this.providerResultService = providerResultService;
        this.imageStorageService = imageStorageService;
        this.awsRekognitionProviderClient = awsRekognitionProviderClient;
        this.googleCloudVisionProviderClient = googleCloudVisionProviderClient;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public List<ProviderResultResponse> analyze(UUID imageId, AnalyzeImageRequest request) {
        var image = imageStorageService.getRequired(imageId);
        List<String> providers = sanitizeProviders(request.providers());
        List<ProviderResultResponse> results = new ArrayList<>();

        for (String provider : providers) {
            MockProviderResult mockResult = resultFor(provider, image);
            results.add(providerResultService.save(new SaveProviderResultRequest(
                    imageId,
                    mockResult.providerName(),
                    mockResult.responseTimeMs(),
                    mockResult.labels(),
                    mockResult.rawResponse()
            ), mockResult.status()));
        }

        return results;
    }

    private List<String> sanitizeProviders(List<String> providers) {
        List<String> sanitized = providers.stream()
                .filter(provider -> provider != null && !provider.isBlank())
                .map(String::trim)
                .distinct()
                .toList();

        if (sanitized.isEmpty()) {
            throw new BadRequestException("At least one provider is required");
        }

        return sanitized;
    }

    private MockProviderResult resultFor(String provider, com.visiontester.backend.domain.ImageAsset image) {
        String normalizedProvider = normalize(provider);

        if (normalizedProvider.equals("aws-rekognition") || normalizedProvider.equals("aws rekognition")) {
            var awsResult = awsRekognitionProviderClient.analyze(image);
            return new MockProviderResult(
                    "AWS Rekognition",
                    ProviderRunStatus.REAL,
                    awsResult.responseTimeMs(),
                    awsResult.labels(),
                    awsResult.rawResponse()
            );
        }

        if (normalizedProvider.equals("google-cloud-vision") || normalizedProvider.equals("google cloud vision")) {
            var googleResult = googleCloudVisionProviderClient.analyze(image);
            return new MockProviderResult(
                    "Google Cloud Vision",
                    ProviderRunStatus.REAL,
                    googleResult.responseTimeMs(),
                    googleResult.labels(),
                    googleResult.rawResponse()
            );
        }

        if (normalizedProvider.equals("mock")) {
            List<ProviderLabelRequest> labels = List.of(
                    new ProviderLabelRequest("Battery", BigDecimal.valueOf(88.7)),
                    new ProviderLabelRequest("Portable Electronics", BigDecimal.valueOf(73.5)),
                    new ProviderLabelRequest("Object", BigDecimal.valueOf(64.2))
            );
            return new MockProviderResult("MOCK", ProviderRunStatus.MOCKED, 420, labels, rawGenericMockResponse(image.getOriginalFilename()));
        }

        throw new BadRequestException("Unsupported provider for analysis: " + provider);
    }

    private String normalize(String provider) {
        return provider.toLowerCase(Locale.ROOT).replace('_', '-');
    }

    private JsonNode rawGenericMockResponse(String imageName) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("provider", "MOCK");
        response.put("executionProvider", "MOCK");
        response.put("executionMode", "backend-mock");
        response.put("imageName", imageName);
        response.put("processingTimeMs", 420);
        response.put("labels", List.of(
                Map.of("name", "Battery", "confidence", 88.7),
                Map.of("name", "Portable Electronics", "confidence", 73.5),
                Map.of("name", "Object", "confidence", 64.2)
        ));
        response.put("generatedAt", OffsetDateTime.now().toString());
        return objectMapper.valueToTree(response);
    }

    private record MockProviderResult(
            String providerName,
            ProviderRunStatus status,
            Integer responseTimeMs,
            List<ProviderLabelRequest> labels,
            JsonNode rawResponse
    ) {
    }
}
