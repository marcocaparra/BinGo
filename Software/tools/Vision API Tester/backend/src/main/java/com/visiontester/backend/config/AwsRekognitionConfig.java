package com.visiontester.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.ProfileCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.rekognition.RekognitionClient;

@Configuration
public class AwsRekognitionConfig {

    @Bean
    public RekognitionClient rekognitionClient(AwsRekognitionProperties properties) {
        return RekognitionClient.builder()
                .credentialsProvider(ProfileCredentialsProvider.builder()
                        .profileName(properties.getProfile())
                        .build())
                .region(Region.of(properties.getRegion()))
                .build();
    }
}
