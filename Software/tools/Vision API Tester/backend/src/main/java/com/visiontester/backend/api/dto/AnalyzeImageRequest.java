package com.visiontester.backend.api.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import java.util.List;

public record AnalyzeImageRequest(
        @NotEmpty @Size(max = 10) List<@Size(max = 80) String> providers
) {
}
