package com.visiontester.backend.config;

import com.google.cloud.vision.v1.ImageAnnotatorClient;
import java.io.IOException;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class GoogleCloudVisionConfig {

    @Bean(destroyMethod = "close")
    public ImageAnnotatorClient imageAnnotatorClient() throws IOException {
        return ImageAnnotatorClient.create();
    }
}
