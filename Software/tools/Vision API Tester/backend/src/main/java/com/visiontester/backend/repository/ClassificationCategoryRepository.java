package com.visiontester.backend.repository;

import com.visiontester.backend.domain.ClassificationCategory;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ClassificationCategoryRepository extends JpaRepository<ClassificationCategory, UUID> {

    @EntityGraph(attributePaths = "aliases")
    Optional<ClassificationCategory> findByCodeIgnoreCase(String code);

    boolean existsByCodeIgnoreCase(String code);

    @EntityGraph(attributePaths = "aliases")
    List<ClassificationCategory> findByActiveTrueOrderByDisplayOrderAscNameAsc();

    @EntityGraph(attributePaths = "aliases")
    @Query("""
            select distinct category
            from ClassificationCategory category
            left join category.aliases alias
            where category.active = true
              and (
                    lower(category.code) like lower(concat('%', :query, '%'))
                    or lower(category.name) like lower(concat('%', :query, '%'))
                    or lower(alias.alias) like lower(concat('%', :query, '%'))
              )
            order by category.displayOrder, category.name
            """)
    List<ClassificationCategory> searchActive(@Param("query") String query);

    @Query("select coalesce(max(category.displayOrder), 0) from ClassificationCategory category")
    int maxDisplayOrder();
}
