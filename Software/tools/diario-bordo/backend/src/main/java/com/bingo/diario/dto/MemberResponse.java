package com.bingo.diario.dto;

import java.util.UUID;

import com.bingo.diario.model.Member;

public record MemberResponse(
        UUID id,
        String name,
        String defaultArea,
        String role,
        boolean isActive) {

    public static MemberResponse from(Member member) {
        return new MemberResponse(
                member.getId(),
                member.getName(),
                member.getDefaultArea(),
                member.getRole(),
                member.isActive());
    }
}
