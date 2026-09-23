package com.visiontester.backend.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.aws.rekognition")
public class AwsRekognitionProperties {

    private String profile = "vision-api-tester";
    private String region = "us-east-1";
    private float minConfidence = 55.0F;
    private int maxLabels = 20;

    public String getProfile() {
        return profile;
    }

    public void setProfile(String profile) {
        this.profile = profile;
    }

    public String getRegion() {
        return region;
    }

    public void setRegion(String region) {
        this.region = region;
    }

    public float getMinConfidence() {
        return minConfidence;
    }

    public void setMinConfidence(float minConfidence) {
        this.minConfidence = minConfidence;
    }

    public int getMaxLabels() {
        return maxLabels;
    }

    public void setMaxLabels(int maxLabels) {
        this.maxLabels = maxLabels;
    }
}
