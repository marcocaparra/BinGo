-- BinGo V1
-- Seed: 008_seed_totem_simulator_rich_demo.sql
--
-- Seed rica de desenvolvimento para o Totem Simulator.
-- Cria uma escola demo com 7 turmas, 70 alunos ativados e PINs reais
-- persistidos como hash compativel com backend/src/infra/crypto/security.py.
--
-- Observacao importante:
-- A coluna demo_pin abaixo existe apenas dentro da CTE da seed para documentar
-- os PINs de desenvolvimento. O banco recebe apenas pin_hash.
--
-- Maquina demo: Totem Demo 01
-- API key demo da maquina: edge-demo-key

delete from redemptions
where school_id = '10000000-0000-4000-8000-000000000001';

delete from deposits
where school_id = '10000000-0000-4000-8000-000000000001';

delete from audit_logs
where school_id = '10000000-0000-4000-8000-000000000001';

delete from students
where school_id = '10000000-0000-4000-8000-000000000001';

delete from classes
where school_id = '10000000-0000-4000-8000-000000000001';

insert into schools (
    id,
    name
)
values (
    '10000000-0000-4000-8000-000000000001',
    'Escola Demo BinGo'
)
on conflict (id) do update
set
    name = excluded.name,
    updated_at = now();

insert into school_settings (
    school_id,
    small_item_daily_limit,
    points_small_student,
    points_small_class,
    points_medium_student,
    points_medium_class,
    points_large_student,
    points_large_class,
    redemption_expiration_hours,
    redemption_daily_limit,
    redemption_max_pending
)
values (
    '10000000-0000-4000-8000-000000000001',
    5,
    10,
    10,
    25,
    25,
    50,
    50,
    72,
    3,
    3
)
on conflict (school_id) do update
set
    small_item_daily_limit = excluded.small_item_daily_limit,
    points_small_student = excluded.points_small_student,
    points_small_class = excluded.points_small_class,
    points_medium_student = excluded.points_medium_student,
    points_medium_class = excluded.points_medium_class,
    points_large_student = excluded.points_large_student,
    points_large_class = excluded.points_large_class,
    redemption_expiration_hours = excluded.redemption_expiration_hours,
    redemption_daily_limit = excluded.redemption_daily_limit,
    redemption_max_pending = excluded.redemption_max_pending,
    updated_at = now();

insert into classes (
    id,
    school_id,
    segment,
    grade,
    name,
    points_class_balance
)
values
('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '6', U&'6\00BA Ano A', 0),
('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '7', U&'7\00BA Ano A', 0),
('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '8', U&'8\00BA Ano A', 0),
('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', 'FUNDAMENTAL_2', '9', U&'9\00BA Ano A', 0),
('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', 'ENSINO_MEDIO', '1', U&'1\00AA S\00E9rie A', 0),
('20000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', 'ENSINO_MEDIO', '2', U&'2\00AA S\00E9rie A', 0),
('20000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001', 'ENSINO_MEDIO', '3', U&'3\00AA S\00E9rie A', 0)
on conflict (id) do update
set
    school_id = excluded.school_id,
    segment = excluded.segment,
    grade = excluded.grade,
    name = excluded.name,
    points_class_balance = excluded.points_class_balance,
    updated_at = now();

with demo_students (
    id,
    class_id,
    name,
    demo_pin,
    pin_hash
) as (
    values
    ('30000000-0000-4000-8000-000000000001'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, 'Ana Castanheira', '4827', 'cyFk4kdbNFaq5m+omkVohA==$SyR/dsE76yHMsMaw6mO+L7hYBOqChGqbh7ZSID20Wys='),
    ('30000000-0000-4000-8000-000000000002'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, 'Bruno Valente', '9361', 'R4bHXayE29oqdGF+1UIcLg==$K9bFqzNt0PH5Yzm4rR7bdLPuBzMDKumuUwqBh6TzME0='),
    ('30000000-0000-4000-8000-000000000003'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, U&'Cec\00EDlia Ramalho', '1749', 'v49jPdgDvniskaHLexusGg==$XHSKlb6XmgrMtnTQpwQh1Vr9WNqajL//WwQ70Hr3VF0='),
    ('30000000-0000-4000-8000-000000000004'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, U&'Diego Mar\00E7al', '6204', 'hXKyzLSxsNaO6OQBZjT6jQ==$+FBroDC+PcYUmkPjEQY/bDiCzoiQqFNrnadDs5vJ+UA='),
    ('30000000-0000-4000-8000-000000000005'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, 'Helena Figueiredo', '7582', 'YF7ztD0mcH5TmKNtxEmDJQ==$IKFtkt55ySi+KAmO8bes1Pf5cE+qY935aNF+znrjFjw='),
    ('30000000-0000-4000-8000-000000000006'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, U&'\00CDcaro Belmonte', '2916', 'U4CugtojpD2APe7Rbw9pnQ==$byZWUcZ0scLzYqirKPadu8J2hjiE1eAATwQsGMt88jo='),
    ('30000000-0000-4000-8000-000000000007'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, 'Lara Seabra', '8450', 'PaT/vFjWpku2k8IE3SLanA==$L356zRPer0lkFtF4mW8R+A6wtCp3M0fXm6bRoi2yS5A='),
    ('30000000-0000-4000-8000-000000000008'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, 'Mateus Goulart', '3678', 'oTrtcDfjKxTLwQ43S/byoA==$x94Sp3iX9GOixUPzM7UNgTfksJO0R0I7SGP7EgDN2e4='),
    ('30000000-0000-4000-8000-000000000009'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, 'Nina Caldeira', '5093', 'fF7W3p9VmSKyQCI2NfM5fg==$1hQf88bQdXnSbWecSUzEkPJ9Vqq7A4uQs+t05TvbVRQ='),
    ('30000000-0000-4000-8000-000000000010'::uuid, '20000000-0000-4000-8000-000000000001'::uuid, U&'Ot\00E1vio Linhares', '2147', 'd1NfX3xlsv9473TXVxGS3g==$uRRUSBdkQTt17/6rcG+IUrAj/8IJJO+xpKAN3wE4THY='),
    ('30000000-0000-4000-8000-000000000011'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'Caio Nogueira', '6815', 'tjdHfOmDyEUwyomEVPPpRg==$t3xdxa8v4+RO9ss5NiSFHm9kG9JU3z+yQJ1sOaoWwrA='),
    ('30000000-0000-4000-8000-000000000012'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'Isabela Monteiro', '4372', 'tr7OEIjdinX6nhZnPCcLCw==$/7XllBf1P4NUi2VsZGlpQdmFpyqpFZ2Swtx6Ku6E4ZA='),
    ('30000000-0000-4000-8000-000000000013'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, U&'Let\00EDcia Vasconcelos', '9206', 'bo+cqN8gzNvjlAUEI6QfqQ==$DXy7ZUdoqhwDGSyixAee81lM2b/J1cU3LthOBHrjgUA='),
    ('30000000-0000-4000-8000-000000000014'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'Murilo Batista', '1538', 'wlcBNCzXJ86Vk2XhC/sy/g==$8D1JIGWXIS+pdtNXSTgUWbIUH2RIZy/aOVyPvTUxD8w='),
    ('30000000-0000-4000-8000-000000000015'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'Sofia Albuquerque', '7049', 'qIPEABw4Uq+YScAOXB88eA==$v8cawjHlmue46RyDmw7Giqpz6pw1NBeY0tqldiuqFZ8='),
    ('30000000-0000-4000-8000-000000000016'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, U&'\00C1lvaro Junqueira', '2681', 'ToDmdHl3eYzn5O1lWOx42A==$N02eDpLEZ4jggZ4q0SWQgyT0QZ6rp/puIHJ0pCMPx/w='),
    ('30000000-0000-4000-8000-000000000017'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'Bruna Paes', '3957', 'D51OJzp1sV8toQxU3iYCUQ==$i5ctCIsTI8fiKs0gXolBC/pkKIC0QKbraIpxvtA+mwk='),
    ('30000000-0000-4000-8000-000000000018'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'Daniel Furtado', '8124', 'ghvxxt4ypBGBfG7BDBQzhA==$0Au1ZqrpAuvloAgSobCQcnKxHJJTY8TXpXpTzdze3h4='),
    ('30000000-0000-4000-8000-000000000019'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, U&'Mait\00EA Sarmento', '0463', 'MUbH2UlO3ETW4iquNBl1sg==$oKekgxKZWuHWKNeJ97kF2Qln5As45PTJsUHRRzEVG0Q='),
    ('30000000-0000-4000-8000-000000000020'::uuid, '20000000-0000-4000-8000-000000000002'::uuid, 'Thiago Noronha', '5790', 'MQTce3goi5n5xH07uQvaWg==$bjBgBZfWI0MFD1n2KVrMbHWHWi0LCXBvabgFkH1M6cQ='),
    ('30000000-0000-4000-8000-000000000021'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Davi Siqueira', '7348', 'nRaA9TXRbbDv7HjZsA58Rw==$Q+7f+Ke9SDvEivfDqNQ0DbI3mPK7pjDZ+gOxWbIhS0k='),
    ('30000000-0000-4000-8000-000000000022'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Elisa Domingues', '1905', '0cCU/lVYM0orrUmdga7k6w==$5aK5W4bDl60MmIjEfXe/DpoS0Bzx9nyLMGy3w/MV1ZQ='),
    ('30000000-0000-4000-8000-000000000023'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Gabriel Rezende', '8621', 'ZjmUz/a9+3vgC/TjApvtog==$gXjWTjJNzmOF5d3M4HhnzsFv+CDuo1sisL35mn6ZSiw='),
    ('30000000-0000-4000-8000-000000000024'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Marina Peixoto', '4167', 'UFq7J+qMdiGjUQ6n8n6KgA==$2obbM/qVUhVdfOVuI8Hq5ILfzNf4GiorkxHH39Sfplc='),
    ('30000000-0000-4000-8000-000000000025'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Rafael Antunes', '5039', 'FqKbOnUw5U6UVk/UIPOmVA==$xwXgg3jrefXoGtPwAySZ/tD1M77rGZMPrAkhsAzw25Y='),
    ('30000000-0000-4000-8000-000000000026'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Amanda Vilela', '2754', 'u8lug7OFJ18NOsDua2kp4Q==$2UrFPQcS7Os22G/dgTRYo0Kg9EIUiPGLVoMTvbhc7kw='),
    ('30000000-0000-4000-8000-000000000027'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Heitor Lacerda', '9482', 'UZsmWLSHMPgSY92iqzeT3w==$RHx3HcbVyQcnB7XNSeaAAMNieyC4E3Gd8mko75mWX70='),
    ('30000000-0000-4000-8000-000000000028'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, U&'L\00EDvia Mascarenhas', '6310', 'tiiWOgguzikWDJnk11vQKA==$bUJEOrvICKeLuYn3vWwqeh7LPfvcK0LZSu5lfU5Hwnc='),
    ('30000000-0000-4000-8000-000000000029'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Nicolas Barreto', '0876', '+7bsRuY6hiIzODqWuL3JOg==$mGaQHWseGY0FA647szGDHoLph8xMg5XjYw/JJ+Gc6Cw='),
    ('30000000-0000-4000-8000-000000000030'::uuid, '20000000-0000-4000-8000-000000000003'::uuid, 'Yasmin Ferraz', '3591', 'BfJFUsOb7ADr7ewTCCif5Q==$XLMCyTrjq2bel17a7/dtJsLe3UD6cHAJj2R2aQatHLo='),
    ('30000000-0000-4000-8000-000000000031'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, 'Bianca Tavares', '6028', 'U/nTa18caL7V7ivgHkXNIg==$ljYmDJ0wA49FFyoEksJU4j+wJYFYedWlIc56pjC5Trg='),
    ('30000000-0000-4000-8000-000000000032'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, 'Enzo Madureira', '1473', '/hBPY5CxFUc6PN1blhtnZg==$1lxKw9VIRDqDuhl4SsMon9rNmHjqXmH3bO9ZzmXxIvw='),
    ('30000000-0000-4000-8000-000000000033'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, U&'J\00FAlia Carvalho', '8950', 'g+nS3xJ1cZXUQRDc3yf3BQ==$4yolywSdB7twE/wXtLUg1xoUnqDp1IkXifVi0yFgBYo='),
    ('30000000-0000-4000-8000-000000000034'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, 'Lorenzo Meireles', '3216', 'sPeOPxIE5NeOdp2WjEjWZA==$7R61/ZA3CKYpQKdPYoMYa6POqgiMwNt9AK0jeNcvxoo='),
    ('30000000-0000-4000-8000-000000000035'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, U&'Vit\00F3ria Assun\00E7\00E3o', '4709', 'AZgYvf6WOv8Le+F5w4RAVg==$LxVt/jVD1FDAHEtNX+tUePQm6JFvGbctelDx9SZHwhY='),
    ('30000000-0000-4000-8000-000000000036'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, U&'Augusto Valen\00E7a', '7531', 'qyzR86eL/W7R1JUdxrFFMQ==$BW+H+OLIp0RciGnVw+5/xRxCv2GjqnmrrX2uBZKN0xE='),
    ('30000000-0000-4000-8000-000000000037'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, 'Catarina Dantas', '2694', 'FwEtjiRNKTL4OKDjmqlAXg==$L5q4TbaOQ4E/Op3ceked1TaoMnvvA+TdHkQisb3cIvQ='),
    ('30000000-0000-4000-8000-000000000038'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, 'Henrique Salgado', '9186', 'XaUlnNPQ1t5T8kyVEoAGWg==$iMtItRODN4LoGWHl28ozCu8qS+ljZsRjJjZ0xQr3PlU='),
    ('30000000-0000-4000-8000-000000000039'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, 'Melissa Fontoura', '0347', '2RJYstQPcBcruG0LwnRTQg==$JP6TPZkz5/aehclSQvbCb/5OgXzm8FutYYAKPXVq4y0='),
    ('30000000-0000-4000-8000-000000000040'::uuid, '20000000-0000-4000-8000-000000000004'::uuid, 'Samuel Abranches', '5862', '/EjTMntsedx02pZXT0DMAQ==$TzgEch/8Tc88S3ZJb8Cf5x1EC3hSkflMTGNJfdjgC0M='),
    ('30000000-0000-4000-8000-000000000041'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, 'Artur Pimentel', '7416', 'edkpHkqZhBpI/XzKzYYM2g==$MCcaoKFFW1mKNZauh9Eljg51s620jfU6I2rPU2mJ+7E='),
    ('30000000-0000-4000-8000-000000000042'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, 'Camila Barreto', '2058', 'UmykI4LVF9Rlpg8katCGJg==$5WpdAaXrf9z7nwRcV6ZvxVtZV3KIrOthJ/5NXwncXGY='),
    ('30000000-0000-4000-8000-000000000043'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, 'Felipe Azevedo', '6893', 'JiCkRPYU5pXsXWR0PHiTMw==$d3q2OyUP6uQ8rOItekUc+P2zeOrZc+tBFVlCqlXh0w4='),
    ('30000000-0000-4000-8000-000000000044'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, U&'Laura Guimar\00E3es', '3170', '1MwtAcTdcY50XD9F2/ISPA==$y/OLXPRYjWEEHZi7LyZxwGhq5iGocFSHyWm85kZp3Bs='),
    ('30000000-0000-4000-8000-000000000045'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, 'Miguel Sampaio', '9542', 'wjMGcXQcCTqR+5YXIw3gtw==$xiwTsIbSJSTUSoWgzI02P9asZFqD0Cee7kVH3U9aGUU='),
    ('30000000-0000-4000-8000-000000000046'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, 'Aline Sabino', '4629', 'iHc9Qrc9g4IN7Wsyv5HlXA==$22ZThHRbHht9boLdJZtz12KM6TwRRLh2mQw7UVTdLkM='),
    ('30000000-0000-4000-8000-000000000047'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, U&'Bento Magalh\00E3es', '8305', '9QJQ/22mWOALxtUnKUGMeg==$3q4nSLktNhEfYpXCYygoA72yiqId22OT3U8xd2vNhro='),
    ('30000000-0000-4000-8000-000000000048'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, 'Estela Chaves', '1764', '1+T5J4w5DtYyKoc5Chhrug==$QGTb4zGsYsNk2Dt0BoyJR0JftsW6xabY0mfNM5u7SzQ='),
    ('30000000-0000-4000-8000-000000000049'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, 'Guilherme Dornelas', '5981', 'CdirXXa3F3uIJIFhwMSMSg==$AVtSGSSBijUssIEoAPkMv+B9FayWNt8+7w7iZEzuaHg='),
    ('30000000-0000-4000-8000-000000000050'::uuid, '20000000-0000-4000-8000-000000000005'::uuid, U&'Ta\00EDs Brand\00E3o', '0239', '3sfIe8zR3NcArFtklsISLQ==$keA9sgrl9TnU8hbqUaaeXzHJWmJO3tGL2o3gJ+NniKw='),
    ('30000000-0000-4000-8000-000000000051'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, 'Alice Ferraz', '6840', 'l0RXbPCPsC25WkuDJ7tO/g==$EA10PhvwO3oBYDsO+ZsfOYy7A1Gi6cM4eQSMPRQKgBQ='),
    ('30000000-0000-4000-8000-000000000052'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, 'Bernardo Coutinho', '1295', '2rBe0mJNC/UcsNNW15a1XQ==$8io/zHPywxxBGMoiRPMkU0o20wPyg4biwCDjGTP7uOw='),
    ('30000000-0000-4000-8000-000000000053'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, 'Clara Junqueira', '7503', 'GS9kkOpaYbtIuFGPzZkfZg==$wWh6V2HLuIZbfU/GUBHKtHUmUWeCD1YS68pCf3X4JbM='),
    ('30000000-0000-4000-8000-000000000054'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, 'Eduardo Amaral', '3968', 'TgeBv8GpbM7VxclpM3z9Mw==$sfb42Wvwtyn66SonJx8TkBGVXUQqAnGxSU/Bsism0+M='),
    ('30000000-0000-4000-8000-000000000055'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, 'Manuela Prado', '2140', 'RY/qgwcovBx4zbUdLELKdQ==$N1Epw+n1HpdJm/XzuZ13Z8Q1WzM3GdE+afGwNwJIlME='),
    ('30000000-0000-4000-8000-000000000056'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, U&'C\00E9sar Toledo', '8697', 'Yz+JP8i+F1ZRpOcDsfT5EQ==$Bi4uJSN99AC2V80qL6RO3BltjIQI/M/ZpV9UVyJntM4='),
    ('30000000-0000-4000-8000-000000000057'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, 'Diana Valadares', '4571', '4+zDe7k6zM6Dq1ZwRieQbw==$atzEAOxdUW/jycZcVGHe764E3+YbT9bSqGuP9zeU99U='),
    ('30000000-0000-4000-8000-000000000058'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, U&'F\00E1bio Cerqueira', '0328', 'x1PEYliJRyW/95UXokVAig==$mXsACbJ3RB2Sy1mCntAzY1kMefOOqhdOym+rTEokohQ='),
    ('30000000-0000-4000-8000-000000000059'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, 'Lorena Bastos', '5916', 'mNYp7F21vKkRppzvRgiZug==$Jkf1ygxI+BEI821ZLRhZake0GO9QBGq8KaBM6F5GEOI='),
    ('30000000-0000-4000-8000-000000000060'::uuid, '20000000-0000-4000-8000-000000000006'::uuid, U&'Vin\00EDcius Portela', '7084', 'TOrrbIL3jtWO6H5ckUy75g==$nP/GLQut+g6/H+JijuZV8QI0wCTvwZG0n3GVVgBm8Mg='),
    ('30000000-0000-4000-8000-000000000061'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Beatriz Lacerda', '9274', 'a2IRzlcEcgTJWgxLIWpIOg==$zkUpOzF/OL6P52rFWjIuPnvVDxeKBZ1USVzO+k4x0eg='),
    ('30000000-0000-4000-8000-000000000062'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Gustavo Vieira', '3518', 're4hOXXkC52sQnI9v12Chw==$Y31EAuh+XQBEYxxh+pNr/iosgFhMDK0QRQa4Q+14cac='),
    ('30000000-0000-4000-8000-000000000063'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Luana Moraes', '8062', 'lO+ovpx0XjSCEUMHubsfxQ==$fbb+6klZ5jLp9HaYlJ1GBvbT73ppkSE2omTzZyjsD4c='),
    ('30000000-0000-4000-8000-000000000064'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Pedro Alencar', '1459', 'Qn2F39BjW9qNnEkI08b8cQ==$t/2aE0RqNGdFHxJy1g39IgpKeYSZvNNoWWJdZ0Z6E6w='),
    ('30000000-0000-4000-8000-000000000065'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Valentina Queiroz', '6703', 'G7+OujXahL/p6aFDJsmt3Q==$R+1G3LHo7AifnEAzDcyoiAo5IkJa7hSp2Vj63fpsBKA='),
    ('30000000-0000-4000-8000-000000000066'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, U&'Andr\00E9 Fagundes', '2846', 'pFtyFmQ6pirDvoSLdDgQXA==$GTwQkcrU0amsWflOogB7vlYfwa6pgUh3TS1rfakYCOU='),
    ('30000000-0000-4000-8000-000000000067'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, U&'Helo\00EDsa Mendon\00E7a', '5137', 'HGYsMfiZDPguejwjNmPiZg==$OYoQlPX3cmvX+P8UE4QHz2ZGJlglzQMPd0hr4JJYY+s='),
    ('30000000-0000-4000-8000-000000000068'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Marcelo Tupan', '0495', 'HcqY2VuKh+Egm+CAg2T5hQ==$9pvgPjdCioZK8FalIoMU0MJrsuoA1sYsgXv9YritrMc='),
    ('30000000-0000-4000-8000-000000000069'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Priscila Albuquerque', '7320', 'AgiNUbha0hTNr0Z3P622tw==$LDjS7WSQkTUPYGqCWNqzlHSqiMRKqHVdZIckb71+faM='),
    ('30000000-0000-4000-8000-000000000070'::uuid, '20000000-0000-4000-8000-000000000007'::uuid, 'Rodrigo Campelo', '9681', 'xDUoMPI0+3+t5SsIOb+tzQ==$CztbC1J5BS8H9oWYcNjZNhAkMQf13M60qmsttRvmL20=')
)
insert into students (
    id,
    school_id,
    class_id,
    name,
    pin_hash,
    is_activated,
    points_student_balance,
    status
)
select
    id,
    '10000000-0000-4000-8000-000000000001',
    class_id,
    name,
    pin_hash,
    true,
    0,
    'ACTIVE'
from demo_students
on conflict (id) do update
set
    school_id = excluded.school_id,
    class_id = excluded.class_id,
    name = excluded.name,
    pin_hash = excluded.pin_hash,
    is_activated = excluded.is_activated,
    points_student_balance = excluded.points_student_balance,
    status = excluded.status,
    updated_at = now();

insert into machines (
    id,
    school_id,
    name,
    status,
    firmware_version,
    bin_full,
    camera_ok,
    net_ok,
    api_key_hash
)
values (
    '40000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'Totem Demo 01',
    'ONLINE',
    'demo-v0',
    false,
    true,
    true,
    'YmluZ28tZGVtby1zYWx0IQ==$M1Bg8EYwAODbcgGwHjImY/4O48MTxxKyE7Vn8BdOMJI='
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    name = excluded.name,
    status = excluded.status,
    firmware_version = excluded.firmware_version,
    bin_full = excluded.bin_full,
    camera_ok = excluded.camera_ok,
    net_ok = excluded.net_ok,
    api_key_hash = excluded.api_key_hash,
    updated_at = now();

insert into rewards (
    id,
    school_id,
    name,
    description,
    cost_points,
    category,
    is_active,
    status,
    stock_qty
)
values
(
    '50000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    U&'\00C1gua/Suco',
    'Bebida simples para teste de resgate futuro',
    30,
    'CANTINA',
    true,
    'AVAILABLE',
    20
),
(
    '50000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000001',
    'Doce simples',
    'Recompensa simples para teste de resgate futuro',
    50,
    'CANTINA',
    true,
    'AVAILABLE',
    15
),
(
    '50000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000001',
    'Brinde BinGo',
    'Brinde escolar para teste de resgate futuro',
    40,
    'ESCOLAR',
    true,
    'AVAILABLE',
    10
)
on conflict (id) do update
set
    school_id = excluded.school_id,
    name = excluded.name,
    description = excluded.description,
    cost_points = excluded.cost_points,
    category = excluded.category,
    is_active = excluded.is_active,
    status = excluded.status,
    stock_qty = excluded.stock_qty,
    updated_at = now();
