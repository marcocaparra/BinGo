package com.visiontester.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.visiontester.backend.domain.ClassificationAlias;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.repository.ClassificationCategoryRepository;
import java.util.List;
import org.junit.jupiter.api.Test;

class ClassificationCategoryServiceTests {

    @Test
    void searchByElectronicDeviceAliasReturnsGenericCategory() {
        ClassificationCategoryRepository repository = mock(ClassificationCategoryRepository.class);
        ClassificationCategory category = new ClassificationCategory(
                "ELECTRONIC_DEVICE",
                "Electronic Device",
                95
        );
        category.addAlias(new ClassificationAlias("Electronic device"));
        when(repository.searchActive("electronic device")).thenReturn(List.of(category));

        ClassificationCategoryService service = new ClassificationCategoryService(repository);
        var result = service.search("electronic device");

        assertEquals(1, result.size());
        assertEquals("ELECTRONIC_DEVICE", result.getFirst().code());
        assertEquals(List.of("Electronic device"), result.getFirst().aliases());
        verify(repository).searchActive("electronic device");
    }
}
