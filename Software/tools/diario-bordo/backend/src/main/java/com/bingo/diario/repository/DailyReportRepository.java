package com.bingo.diario.repository;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import com.bingo.diario.model.DailyReport;

public interface DailyReportRepository extends JpaRepository<DailyReport, UUID> {

    boolean existsByMember_IdAndReportDate(UUID memberId, LocalDate reportDate);

    @EntityGraph(attributePaths = "member")
    List<DailyReport> findAllByOrderByReportDateDescSubmittedAtDesc();
}
