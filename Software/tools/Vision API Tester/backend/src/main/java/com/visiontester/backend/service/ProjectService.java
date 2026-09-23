package com.visiontester.backend.service;

import com.visiontester.backend.api.dto.CreateProjectRequest;
import com.visiontester.backend.api.dto.ProjectResponse;
import com.visiontester.backend.domain.Project;
import com.visiontester.backend.repository.ProjectRepository;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProjectService {

    private final ProjectRepository projectRepository;
    private final DtoMapper mapper;

    public ProjectService(ProjectRepository projectRepository, DtoMapper mapper) {
        this.projectRepository = projectRepository;
        this.mapper = mapper;
    }

    @Transactional
    public ProjectResponse create(CreateProjectRequest request) {
        if (projectRepository.existsByNameIgnoreCase(request.name())) {
            throw new BadRequestException("Project name already exists");
        }

        Project project = projectRepository.save(new Project(request.name().trim(), request.description()));
        return mapper.toProjectResponse(project);
    }

    @Transactional(readOnly = true)
    public List<ProjectResponse> list() {
        return projectRepository.findAll().stream()
                .map(mapper::toProjectResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public Project getRequired(UUID projectId) {
        return projectRepository.findById(projectId)
                .orElseThrow(() -> new ResourceNotFoundException("Project not found"));
    }
}
