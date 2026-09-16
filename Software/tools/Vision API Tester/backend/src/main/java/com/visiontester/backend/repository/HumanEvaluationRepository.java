package com.visiontester.backend.repository;

import com.visiontester.backend.domain.EvaluationResult;
import com.visiontester.backend.domain.HumanEvaluation;
import com.visiontester.backend.domain.ProviderRun;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface HumanEvaluationRepository extends JpaRepository<HumanEvaluation, UUID> {

    Optional<HumanEvaluation> findByProviderRun(ProviderRun providerRun);

    Optional<HumanEvaluation> findByProviderRun_Id(UUID providerRunId);

    @Query("""
            select distinct he
            from HumanEvaluation he
            join fetch he.providerRun pr
            join fetch pr.image image
            left join fetch pr.labels labels
            """)
    List<HumanEvaluation> findAllForDashboard();

    @Query("""
            select distinct he
            from HumanEvaluation he
            join fetch he.providerRun pr
            join fetch pr.image image
            left join fetch pr.labels labels
            where image.project.id = :projectId
            """)
    List<HumanEvaluation> findAllForDashboardByProjectId(@Param("projectId") UUID projectId);

    long countByEvaluationResult(EvaluationResult evaluationResult);

    @Query("select count(he) from HumanEvaluation he where he.providerRun.image.project.id = :projectId")
    long countByProjectId(@Param("projectId") UUID projectId);

    @Query("""
            select count(he)
            from HumanEvaluation he
            where he.providerRun.image.project.id = :projectId
              and he.evaluationResult = :evaluationResult
            """)
    long countByProjectIdAndEvaluationResult(
            @Param("projectId") UUID projectId,
            @Param("evaluationResult") EvaluationResult evaluationResult
    );

    @Query("""
            select he.correctClass.code, count(he), sum(case when he.evaluationResult = com.visiontester.backend.domain.EvaluationResult.CORRECT then 1 else 0 end)
            from HumanEvaluation he
            group by he.correctClass.code
            order by he.correctClass.code
            """)
    List<Object[]> summarizeByClass();

    @Query("""
            select he.correctClass.code, count(he), sum(case when he.evaluationResult = com.visiontester.backend.domain.EvaluationResult.CORRECT then 1 else 0 end)
            from HumanEvaluation he
            where he.providerRun.image.project.id = :projectId
            group by he.correctClass.code
            order by he.correctClass.code
            """)
    List<Object[]> summarizeByClassAndProjectId(@Param("projectId") UUID projectId);
}
