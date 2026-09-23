package com.visiontester.backend.api;

import com.visiontester.backend.api.dto.ProviderResultResponse;
import com.visiontester.backend.api.dto.SaveProviderResultRequest;
import com.visiontester.backend.service.ProviderResultService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/provider-results")
public class ProviderResultController {

    private final ProviderResultService providerResultService;

    public ProviderResultController(ProviderResultService providerResultService) {
        this.providerResultService = providerResultService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ProviderResultResponse save(@Valid @RequestBody SaveProviderResultRequest request) {
        return providerResultService.save(request);
    }

    @GetMapping
    public List<ProviderResultResponse> listByImage(@RequestParam UUID imageId) {
        return providerResultService.listByImage(imageId);
    }

}
