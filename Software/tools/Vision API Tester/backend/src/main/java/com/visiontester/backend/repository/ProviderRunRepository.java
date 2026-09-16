package com.visiontester.backend.repository;

import com.visiontester.backend.domain.ProviderRun;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ProviderRunRepository extends JpaRepository<ProviderRun, UUID> {

    @EntityGraph(attributePaths = "labels")
    List<ProviderRun> findByImage_Id(UUID imageId);

    @Query("""
            select distinct pr
            from ProviderRun pr
            join fetch pr.image image
            left join fetch pr.labels labels
            """)
    List<ProviderRun> findAllForDashboard();

    @Query("""
            select distinct pr
            from ProviderRun pr
            join fetch pr.image image
            left join fetch pr.labels labels
            where image.project.id = :projectId
            """)
    List<ProviderRun> findAllForDashboardByProjectId(@Param("projectId") UUID projectId);

    @Query("select count(pr) from ProviderRun pr where pr.image.project.id = :projectId")
    long countByProjectId(@Param("projectId") UUID projectId);

    @Query("select avg(pr.responseTimeMs) from ProviderRun pr")
    Double averageResponseTimeMs();

    @Query("select avg(pr.responseTimeMs) from ProviderRun pr where pr.image.project.id = :projectId")
    Double averageResponseTimeMsByProjectId(@Param("projectId") UUID projectId);

    @Query("""
            select pr.provider, count(pr), avg(pr.responseTimeMs)
            from ProviderRun pr
            group by pr.provider
            order by pr.provider
            """)
    List<Object[]> summarizeByProvider();

    @Query("""
            select pr.provider, count(pr), avg(pr.responseTimeMs)
            from ProviderRun pr
            where pr.image.project.id = :projectId
            group by pr.provider
            order by pr.provider
            """)
    List<Object[]> summarizeByProviderAndProjectId(@Param("projectId") UUID projectId);
}
