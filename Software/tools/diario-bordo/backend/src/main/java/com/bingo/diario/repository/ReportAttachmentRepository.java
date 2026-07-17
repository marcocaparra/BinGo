package com.bingo.diario.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.bingo.diario.model.ReportAttachment;

public interface ReportAttachmentRepository extends JpaRepository<ReportAttachment, UUID> {

    List<ReportAttachment> findAllByReport_IdOrderByUploadedAtAsc(UUID reportId);

    Optional<ReportAttachment> findByIdAndReport_Id(UUID id, UUID reportId);
}
