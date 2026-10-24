"""Integrações concretas com o backend central e futuros componentes locais.

Clientes remotos deverão manter credenciais exclusivamente neste processo e
consumir as Edge Functions oficiais. Clientes locais intermediarão os componentes
controller/ e camera/ do TotemEdge, sem drivers físicos nas rotas ou serviços.
O cliente Supabase implementa somente health-v1; não há protocolo físico.
"""
