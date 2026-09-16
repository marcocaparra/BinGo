package com.visiontester.backend.repository;

import com.visiontester.backend.domain.Project;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectRepository extends JpaRepository<Project, UUID> {

    boolean existsByNameIgnoreCase(String name);

    Optional<Project> findByNameIgnoreCase(String name);
}
