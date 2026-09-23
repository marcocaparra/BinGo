package com.visiontester.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.visiontester.backend.domain.ImageAsset;
import com.visiontester.backend.domain.Project;
import com.visiontester.backend.repository.HumanEvaluationRepository;
import com.visiontester.backend.repository.ImageAssetRepository;
import com.visiontester.backend.repository.ImageValidationRepository;
import com.visiontester.backend.repository.ProviderRunRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class HistoryServiceTests {

    @Test
    void getReturnsTheRequestedImageUsingTheHistoryContract() {
        ImageAssetRepository imageRepository = mock(ImageAssetRepository.class);
        ProviderRunRepository providerRunRepository = mock(ProviderRunRepository.class);
        ImageValidationRepository validationRepository = mock(ImageValidationRepository.class);
        Project project = new Project("history-project", "test");
        ImageAsset image = new ImageAsset(
                project,
                "keyboard.jpg",
                "stored-keyboard.jpg",
                "uploads/stored-keyboard.jpg",
                "image/jpeg",
                128,
                "0".repeat(64),
                640,
                480
        );
        when(imageRepository.findById(image.getId())).thenReturn(Optional.of(image));
        when(providerRunRepository.findByImage_Id(image.getId())).thenReturn(List.of());
        when(validationRepository.findByImage_Id(image.getId())).thenReturn(Optional.empty());

        HistoryService service = service(imageRepository, providerRunRepository, validationRepository);
        var result = service.get(image.getId());

        assertEquals(image.getId(), result.imageId());
        assertEquals("keyboard.jpg", result.imageName());
        assertEquals(project.getId(), result.projectId());
        assertEquals(List.of(), result.providerResults());
    }

    @Test
    void getRejectsAnUnknownImage() {
        ImageAssetRepository imageRepository = mock(ImageAssetRepository.class);
        UUID imageId = UUID.randomUUID();
        when(imageRepository.findById(imageId)).thenReturn(Optional.empty());

        HistoryService service = service(
                imageRepository,
                mock(ProviderRunRepository.class),
                mock(ImageValidationRepository.class)
        );

        assertThrows(ResourceNotFoundException.class, () -> service.get(imageId));
    }

    private HistoryService service(
            ImageAssetRepository imageRepository,
            ProviderRunRepository providerRunRepository,
            ImageValidationRepository validationRepository
    ) {
        return new HistoryService(
                imageRepository,
                providerRunRepository,
                mock(HumanEvaluationRepository.class),
                validationRepository,
                mock(DtoMapper.class)
        );
    }
}
