package com.bingo.diario.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.bingo.diario.model.Member;

public interface MemberRepository extends JpaRepository<Member, UUID> {

    List<Member> findAllByIsActiveTrueOrderByNameAsc();

    Optional<Member> findByIdAndIsActiveTrue(UUID id);
}
