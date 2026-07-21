package com.bingo.diario.service;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.bingo.diario.dto.MemberResponse;
import com.bingo.diario.repository.MemberRepository;

@Service
@Transactional(readOnly = true)
public class MemberService {

    private final MemberRepository memberRepository;

    public MemberService(MemberRepository memberRepository) {
        this.memberRepository = memberRepository;
    }

    public List<MemberResponse> listActiveMembers() {
        return memberRepository.findAllByIsActiveTrueOrderByNameAsc()
                .stream()
                .map(MemberResponse::from)
                .toList();
    }
}
