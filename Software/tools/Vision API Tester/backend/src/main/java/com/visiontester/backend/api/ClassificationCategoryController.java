package com.visiontester.backend.api;

import com.visiontester.backend.api.dto.ClassificationCategoryResponse;
import com.visiontester.backend.api.dto.CreateClassificationCategoryRequest;
import com.visiontester.backend.service.ClassificationCategoryService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/classification-categories")
public class ClassificationCategoryController {

    private final ClassificationCategoryService service;

    public ClassificationCategoryController(ClassificationCategoryService service) {
        this.service = service;
    }

    @GetMapping
    public List<ClassificationCategoryResponse> search(@RequestParam(required = false) String q) {
        return service.search(q);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ClassificationCategoryResponse create(@Valid @RequestBody CreateClassificationCategoryRequest request) {
        return service.create(request);
    }
}
