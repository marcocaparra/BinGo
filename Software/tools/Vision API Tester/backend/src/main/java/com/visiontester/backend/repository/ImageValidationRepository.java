package com.visiontester.backend.repository;

import com.visiontester.backend.domain.ImageValidation;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ImageValidationRepository extends JpaRepository<ImageValidation, UUID> {

    Optional<ImageValidation> findByImage_Id(UUID imageId);

    @Query("""
            select iv
            from ImageValidation iv
            join fetch iv.image image
            left join fetch iv.humanConfirmedClass
            """)
    List<ImageValidation> findAllForDashboard();

    @Query("""
            select iv
            from ImageValidation iv
            join fetch iv.image image
            left join fetch iv.humanConfirmedClass
            where image.project.id = :projectId
            """)
    List<ImageValidation> findAllForDashboardByProjectId(@Param("projectId") UUID projectId);
}
