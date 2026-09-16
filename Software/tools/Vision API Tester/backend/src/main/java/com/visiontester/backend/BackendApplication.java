package com.visiontester.backend;

import com.visiontester.backend.config.AwsRekognitionProperties;
import com.visiontester.backend.config.GoogleCloudVisionProperties;
import com.visiontester.backend.config.StorageProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@EnableConfigurationProperties({StorageProperties.class, AwsRekognitionProperties.class, GoogleCloudVisionProperties.class})
public class BackendApplication {

	public static void main(String[] args) {
		SpringApplication.run(BackendApplication.class, args);
	}

}
