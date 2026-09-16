package com.visiontester.backend.repository;

import com.visiontester.backend.domain.ImageAsset;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ImageAssetRepository extends JpaRepository<ImageAsset, UUID> {

    List<ImageAsset> findTop50ByOrderByCreatedAtDesc();

    List<ImageAsset> findTop50ByProject_IdOrderByCreatedAtDesc(UUID projectId);

    long countByProject_Id(UUID projectId);
}
