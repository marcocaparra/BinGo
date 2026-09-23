package com.visiontester.backend.service;

import com.google.cloud.vision.v1.AnnotateImageRequest;
import com.google.cloud.vision.v1.AnnotateImageResponse;
import com.google.cloud.vision.v1.BatchAnnotateImagesResponse;
import com.google.cloud.vision.v1.EntityAnnotation;
import com.google.cloud.vision.v1.Feature;
import com.google.cloud.vision.v1.Image;
import com.google.cloud.vision.v1.ImageAnnotatorClient;
import com.google.protobuf.ByteString;
import com.google.protobuf.util.JsonFormat;
import com.visiontester.backend.api.dto.ProviderLabelRequest;
import com.visiontester.backend.config.GoogleCloudVisionProperties;
import com.visiontester.backend.domain.ImageAsset;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Component
public class GoogleCloudVisionProviderClient {

    private final ImageAnnotatorClient imageAnnotatorClient;
    private final GoogleCloudVisionProperties properties;
    private final ObjectMapper objectMapper;

    public GoogleCloudVisionProviderClient(
            ImageAnnotatorClient imageAnnotatorClient,
            GoogleCloudVisionProperties properties,
            ObjectMapper objectMapper
    ) {
        this.imageAnnotatorClient = imageAnnotatorClient;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    public GoogleProviderResult analyze(ImageAsset image) {
        long startedAt = System.nanoTime();

        try {
            byte[] bytes = Files.readAllBytes(Path.of(image.getStoragePath()));
            AnnotateImageRequest request = AnnotateImageRequest.newBuilder()
                    .setImage(Image.newBuilder()
                            .setContent(ByteString.copyFrom(bytes))
                            .build())
                    .addFeatures(Feature.newBuilder()
                            .setType(Feature.Type.LABEL_DETECTION)
                            .setMaxResults(properties.getMaxResults())
                            .build())
                    .build();

            BatchAnnotateImagesResponse batchResponse = imageAnnotatorClient.batchAnnotateImages(List.of(request));
            AnnotateImageResponse response = batchResponse.getResponses(0);

            if (response.hasError()) {
                throw new BadRequestException("Google Cloud Vision analysis failed: " + response.getError().getMessage());
            }

            int responseTimeMs = (int) Math.round((System.nanoTime() - startedAt) / 1_000_000.0);

            return new GoogleProviderResult(
                    responseTimeMs,
                    toLabelRequests(response.getLabelAnnotationsList()),
                    toRawResponse(image, response, responseTimeMs)
            );
        } catch (BadRequestException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new BadRequestException("Google Cloud Vision analysis failed: " + exception.getMessage());
        }
    }

    private List<ProviderLabelRequest> toLabelRequests(List<EntityAnnotation> labels) {
        return labels.stream()
                .map(label -> new ProviderLabelRequest(
                        label.getDescription(),
                        BigDecimal.valueOf(confidence(label.getScore() * 100.0F))
                ))
                .toList();
    }

    private JsonNode toRawResponse(ImageAsset image, AnnotateImageResponse response, int responseTimeMs) throws Exception {
        String providerResponseJson = JsonFormat.printer()
                .preservingProtoFieldNames()
                .print(response);

        Map<String, Object> rawResponse = new LinkedHashMap<>();
        rawResponse.put("provider", "Google Cloud Vision");
        rawResponse.put("executionProvider", "GOOGLE_CLOUD_VISION");
        rawResponse.put("executionMode", "real");
        rawResponse.put("projectId", properties.getProjectId());
        rawResponse.put("imageId", image.getId().toString());
        rawResponse.put("imageName", image.getOriginalFilename());
        rawResponse.put("processingTimeMs", responseTimeMs);
        rawResponse.put("response", objectMapper.readTree(providerResponseJson));
        rawResponse.put("generatedAt", OffsetDateTime.now().toString());

        return objectMapper.valueToTree(rawResponse);
    }

    private double confidence(Float value) {
        return value == null ? 0.0 : Math.round(value.doubleValue() * 1000.0) / 1000.0;
    }

    public record GoogleProviderResult(
            Integer responseTimeMs,
            List<ProviderLabelRequest> labels,
            JsonNode rawResponse
    ) {
    }
}
