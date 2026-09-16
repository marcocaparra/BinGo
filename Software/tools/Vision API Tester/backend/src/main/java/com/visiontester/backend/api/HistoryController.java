package com.visiontester.backend.api;

import com.visiontester.backend.api.dto.HistoryItemResponse;
import com.visiontester.backend.service.HistoryService;
import java.util.List;
import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/history")
public class HistoryController {

    private final HistoryService historyService;

    public HistoryController(HistoryService historyService) {
        this.historyService = historyService;
    }

    @GetMapping
    public List<HistoryItemResponse> list(@RequestParam(required = false) UUID projectId) {
        return historyService.list(projectId);
    }

    @GetMapping("/{imageId}")
    public HistoryItemResponse get(@PathVariable UUID imageId) {
        return historyService.get(imageId);
    }
}
