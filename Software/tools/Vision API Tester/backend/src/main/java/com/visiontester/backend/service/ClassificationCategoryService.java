package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.ClassificationCategoryResponse;
import com.visiontester.backend.api.dto.CreateClassificationCategoryRequest;
import com.visiontester.backend.domain.ClassificationAlias;
import com.visiontester.backend.domain.ClassificationCategory;
import com.visiontester.backend.domain.ClassificationCategoryType;
import com.visiontester.backend.domain.EwasteEligibility;
import com.visiontester.backend.repository.ClassificationCategoryRepository;
import java.text.Normalizer;
import java.util.List;
import java.util.Locale;
import java.util.LinkedHashMap;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClassificationCategoryService {

    private final ClassificationCategoryRepository repository;

    public ClassificationCategoryService(ClassificationCategoryRepository repository) {
        this.repository = repository;
    }

    @Transactional(readOnly = true)
    public List<ClassificationCategoryResponse> search(String query) {
        String normalizedQuery = query == null || query.isBlank() ? null : query.trim();
        List<ClassificationCategory> categories = normalizedQuery == null
                ? repository.findByActiveTrueOrderByDisplayOrderAscNameAsc()
                : repository.searchActive(normalizedQuery);

        return categories.stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional
    public ClassificationCategoryResponse create(CreateClassificationCategoryRequest request) {
        String name = request.name().trim();
        String code = request.code() == null || request.code().isBlank()
                ? codeFromName(name)
                : codeFromName(request.code());

        if (repository.existsByCodeIgnoreCase(code)) {
            throw new BadRequestException("Classification category already exists: " + code);
        }

        ClassificationCategory category = new ClassificationCategory(code, name, repository.maxDisplayOrder() + 10);
        category.configureClassification(
                request.categoryType() == null ? ClassificationCategoryType.SPECIFIC : request.categoryType(),
                request.defaultEwasteEligibility() == null
                        ? EwasteEligibility.REVIEW
                        : request.defaultEwasteEligibility()
        );
        normalizedAliases(request.aliases()).forEach(alias ->
                category.addAlias(new ClassificationAlias(alias))
        );
        return toResponse(repository.save(category));
    }

    @Transactional(readOnly = true)
    public ClassificationCategory getRequired(UUID id) {
        return repository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Classification category not found"));
    }

    private ClassificationCategoryResponse toResponse(ClassificationCategory category) {
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

    private List<String> normalizedAliases(List<String> aliases) {
        if (aliases == null) {
            return List.of();
        }

        LinkedHashMap<String, String> unique = new LinkedHashMap<>();
        aliases.stream()
                .map(String::trim)
                .filter(alias -> !alias.isBlank())
                .forEach(alias -> unique.putIfAbsent(alias.toLowerCase(Locale.ROOT), alias));
        return List.copyOf(unique.values());
    }

    private String codeFromName(String value) {
        String normalized = Normalizer.normalize(value.trim(), Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .toUpperCase(Locale.ROOT)
                .replaceAll("[^A-Z0-9]+", "_")
                .replaceAll("^_+|_+$", "");

        if (normalized.isBlank()) {
            throw new BadRequestException("Classification category code cannot be empty");
        }

        return normalized;
    }
}
