package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.ProviderLabelRequest;
import com.visiontester.backend.config.AwsRekognitionProperties;
import com.visiontester.backend.domain.ImageAsset;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.rekognition.RekognitionClient;
import software.amazon.awssdk.services.rekognition.model.BoundingBox;
import software.amazon.awssdk.services.rekognition.model.DetectLabelsRequest;
import software.amazon.awssdk.services.rekognition.model.DetectLabelsResponse;
import software.amazon.awssdk.services.rekognition.model.Image;
import software.amazon.awssdk.services.rekognition.model.Instance;
import software.amazon.awssdk.services.rekognition.model.Label;
import software.amazon.awssdk.services.rekognition.model.Parent;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Component
public class AwsRekognitionProviderClient {

    private static final long MAX_DIRECT_IMAGE_BYTES = 5L * 1024L * 1024L;

    private final RekognitionClient rekognitionClient;
    private final AwsRekognitionProperties properties;
    private final ObjectMapper objectMapper;

    public AwsRekognitionProviderClient(
            RekognitionClient rekognitionClient,
            AwsRekognitionProperties properties,
            ObjectMapper objectMapper
    ) {
        this.rekognitionClient = rekognitionClient;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    public AwsProviderResult analyze(ImageAsset image) {
        if (image.getSizeBytes() > MAX_DIRECT_IMAGE_BYTES) {
            throw new BadRequestException("AWS Rekognition direct byte upload supports images up to 5 MB. Use a smaller image.");
        }

        long startedAt = System.nanoTime();

        try {
            byte[] bytes = Files.readAllBytes(Path.of(image.getStoragePath()));
            DetectLabelsResponse response = rekognitionClient.detectLabels(DetectLabelsRequest.builder()
                    .image(Image.builder()
                            .bytes(SdkBytes.fromByteArray(bytes))
                            .build())
                    .maxLabels(properties.getMaxLabels())
                    .minConfidence(properties.getMinConfidence())
                    .build());
            int responseTimeMs = (int) Math.round((System.nanoTime() - startedAt) / 1_000_000.0);

            return new AwsProviderResult(
                    responseTimeMs,
                    toLabelRequests(response.labels()),
                    toRawResponse(image, response, responseTimeMs)
            );
        } catch (SdkException exception) {
            throw new BadRequestException("AWS Rekognition analysis failed: " + exception.getMessage());
        } catch (Exception exception) {
            throw new BadRequestException("Could not read image for AWS Rekognition: " + exception.getMessage());
        }
    }

    private List<ProviderLabelRequest> toLabelRequests(List<Label> labels) {
        return labels.stream()
                .map(label -> new ProviderLabelRequest(
                        label.name(),
                        BigDecimal.valueOf(confidence(label.confidence()))
                ))
                .toList();
    }

    private JsonNode toRawResponse(ImageAsset image, DetectLabelsResponse response, int responseTimeMs) {
        Map<String, Object> rawResponse = new LinkedHashMap<>();
        rawResponse.put("provider", "AWS Rekognition");
        rawResponse.put("executionProvider", "AWS_REKOGNITION");
        rawResponse.put("executionMode", "real");
        rawResponse.put("imageId", image.getId().toString());
        rawResponse.put("imageName", image.getOriginalFilename());
        rawResponse.put("processingTimeMs", responseTimeMs);
        rawResponse.put("LabelModelVersion", response.labelModelVersion());
        rawResponse.put("Labels", response.labels().stream().map(this::toRawLabel).toList());
        rawResponse.put("ResponseMetadata", Map.of(
                "RequestId", response.responseMetadata().requestId(),
                "HTTPStatusCode", response.sdkHttpResponse().statusCode()
        ));
        rawResponse.put("generatedAt", OffsetDateTime.now().toString());

        return objectMapper.valueToTree(rawResponse);
    }

    private Map<String, Object> toRawLabel(Label label) {
        Map<String, Object> rawLabel = new LinkedHashMap<>();
        rawLabel.put("Name", label.name());
        rawLabel.put("Confidence", confidence(label.confidence()));
        rawLabel.put("Parents", label.parents().stream().map(this::toRawParent).toList());
        rawLabel.put("Instances", label.instances().stream().map(this::toRawInstance).toList());
        return rawLabel;
    }

    private Map<String, Object> toRawParent(Parent parent) {
        return Map.of("Name", parent.name());
    }

    private Map<String, Object> toRawInstance(Instance instance) {
        Map<String, Object> rawInstance = new LinkedHashMap<>();
        rawInstance.put("Confidence", confidence(instance.confidence()));
        if (instance.boundingBox() != null) {
            rawInstance.put("BoundingBox", toRawBoundingBox(instance.boundingBox()));
        }
        return rawInstance;
    }

    private Map<String, Object> toRawBoundingBox(BoundingBox boundingBox) {
        Map<String, Object> rawBoundingBox = new LinkedHashMap<>();
        rawBoundingBox.put("Width", confidence(boundingBox.width()));
        rawBoundingBox.put("Height", confidence(boundingBox.height()));
        rawBoundingBox.put("Left", confidence(boundingBox.left()));
        rawBoundingBox.put("Top", confidence(boundingBox.top()));
        return rawBoundingBox;
    }

    private double confidence(Float value) {
        return value == null ? 0.0 : Math.round(value.doubleValue() * 1000.0) / 1000.0;
    }

    public record AwsProviderResult(
            Integer responseTimeMs,
            List<ProviderLabelRequest> labels,
            JsonNode rawResponse
    ) {
    }
}
