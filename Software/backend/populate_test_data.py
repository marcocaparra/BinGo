import os
import sys
from pathlib import Path
import secrets
import string
from datetime import datetime, timedelta, UTC
import json
import re
import unicodedata

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

current_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(current_dir))

from base_class import Base
from database import DOCKER_SQLALCHEMY_DATABASE_URL

import models
from models.user_model import User
from models.material_type_model import MaterialType
from models.mission_model import Mission, UserMission
from models.unique_code_model import UniqueCode
from models.discard_model import Discard
from models.achievement_model import Achievement, UserAchievement
from models.reward_model import Reward
from auth import get_password_hash
from services.achievement_service import AchievementConditionType

script_engine = create_engine(DOCKER_SQLALCHEMY_DATABASE_URL)
ScriptSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=script_engine)

def slugify(text: str) -> str:
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^a-zA-Z0-9\s-]", "", text)
    text = re.sub(r"\s+", "-", text.strip().lower())
    text = re.sub(r"-{2,}", "-", text)
    return text

def badge_url_from_name(name: str, ext: str = "png") -> str:
    """
    IMPORTANTE:
    Como você acessa as páginas em dev via /public/profile.html,
    as imagens ficam expostas em /public/assets/...
    """
    return f"/public/assets/badges/{slugify(name)}.{ext}"


def get_db_session():
    return ScriptSessionLocal()

def ensure_schema_fresh():
    print("Limpando e recriando o schema do banco de dados...")
    with script_engine.connect() as connection:
        connection.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))
        connection.commit()
        Base.metadata.drop_all(bind=script_engine)
        Base.metadata.create_all(bind=script_engine)
        connection.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))
        connection.commit()
    print("Schema recriado com sucesso.")

def upsert_material(db, name, points_per_unit):
    m = db.query(MaterialType).filter(MaterialType.name == name).first()
    if not m:
        m = MaterialType(name=name, points_per_unit=points_per_unit)
        db.add(m)
        db.commit()
        db.refresh(m)
    else:
        m.points_per_unit = points_per_unit
        db.add(m)
        db.commit()
        db.refresh(m)
    return m

def generate_code(db, length=6, material_type_id=None):
    chars = string.ascii_uppercase + string.digits
    while True:
        code_str = ''.join(secrets.choice(chars) for _ in range(length))
        exists = db.query(UniqueCode).filter(UniqueCode.code == code_str).first()
        if not exists:
            break
    c = UniqueCode(code=code_str, is_used=False, material_type_id=material_type_id)
    db.add(c)
    db.commit()
    db.refresh(c)
    return c.code

def fake_cpf_from_id(i: int) -> str:
    return str(10_000_000_000 + i)[-11:]

def fake_phone_from_id(i: int) -> str:
    return f"(11)9{(7000 + i) % 10000:04d}-{(3000 + i) % 10000:04d}"


def ensure_users(db):
    print("Garantindo a existência de usuários...")
    names = [
        "Test User", "Ana Silva", "Bruno Costa", "Carla Souza", "Diego Lima",
        "Eva Martins", "Felipe Alves", "Gabi Rocha", "Henrique Dias", "Iara Nunes"
    ]
    base_pass = "testpassword123"
    hashed = get_password_hash(base_pass)
    users = []
    for i, name in enumerate(names, start=1):
        username = f"user{i}"
        email = f"user{i}@example.com"
        u = db.query(User).filter(User.email == email).first()
        if not u:
            u = User(
                username=username,
                email=email,
                hashed_password=hashed,
                name=name,
                cpf=fake_cpf_from_id(i),
                phone_number=fake_phone_from_id(i),
                total_points=0.0,
                level=1,
                discard_count=0,
                mission_completed_count=0
            )
            db.add(u)
            db.commit()
            db.refresh(u)
        else:
            u.hashed_password = hashed
            u.total_points = 0.0
            u.level = 1
            u.discard_count = 0
            u.mission_completed_count = 0
            if not u.cpf:
                u.cpf = fake_cpf_from_id(i)
            if not u.phone_number:
                u.phone_number = fake_phone_from_id(i)
            db.add(u)
            db.commit()
            db.refresh(u)
        users.append(u)
    return users


def ensure_achievements(db, material_e_id):
    print("Garantindo a existência de conquistas...")
    spec = [
        {
            "name": "Primeiro Descarte",
            "description": "Realize seu primeiro descarte e ganhe 20 Bins.",
            "criteria_json": {"type": AchievementConditionType.FIRST_DISCARD},
            "points_reward": 20,
        },
        {
            "name": "Eco-Novato",
            "description": "Alcance 100 Bins totais.",
            "criteria_json": {
                "type": AchievementConditionType.TOTAL_POINTS_REACHED,
                "target": 100
            },
            "points_reward": 20,
        },
        {
            "name": "Descarte Eletrônico",
            "description": "Descarte seu primeiro item eletrônico.",
            "criteria_json": {
                "type": AchievementConditionType.SPECIFIC_MATERIAL_DISCARD_COUNT,
                "material_type_id": material_e_id,
                "target": 1
            },
            "points_reward": 20,
        },
        {
            "name": "Mestre do Descarte",
            "description": "Realize 5 descartes de qualquer tipo.",
            "criteria_json": {
                "type": AchievementConditionType.TOTAL_DISCARDS_COUNT,
                "target": 5
            },
            "points_reward": 20,
        },
    ]

    for item in spec:
        name = item["name"]
        image_url = badge_url_from_name(name)
        a = db.query(Achievement).filter(Achievement.name == name).first()
        if not a:
            a = Achievement(
                name=name,
                description=item["description"],
                criteria_json=item["criteria_json"],
                points_reward=item["points_reward"],
                badge_image_url=image_url,
                is_active=True,
            )
            db.add(a)
            db.commit()
            db.refresh(a)
        else:
            a.description = item["description"]
            a.criteria_json = item["criteria_json"]
            a.points_reward = item["points_reward"]
            a.badge_image_url = image_url
            a.is_active = True
            db.add(a)
            db.commit()
            db.refresh(a)


def ensure_missions(db, material_e_id, material_ne_id):
    print("Garantindo a existência de missões...")
    reward = 20
    now = datetime.now(UTC)
    end = now + timedelta(days=30)
    spec = [
        ("Comece Agora", "Aceite sua primeira missão e complete 1 descarte.", {"action_type": "discard"}, reward, "discard_count", 1),
        ("Trinca Sustentável", "Realize 3 descartes de qualquer tipo.", {"action_type": "discard"}, reward, "discard_count", 3),
        ("Eletrônicos Iniciante", "Descarte 1 item eletrônico.", {"action_type": "discard", "material_type_id": material_e_id}, reward, "discard_specific_material", 1),
        ("Eletrônicos Focado", "Descarte 2 itens eletrônicos.", {"action_type": "discard", "material_type_id": material_e_id}, reward, "discard_specific_material", 2),
        ("Não Eletrônicos Iniciante", "Descarte 1 item não eletrônico.", {"action_type": "discard", "material_type_id": material_ne_id}, reward, "discard_specific_material", 1),
        ("Não Eletrônicos Focado", "Descarte 2 itens não eletrônicos.", {"action_type": "discard", "material_type_id": material_ne_id}, reward, "discard_specific_material", 2),
        ("Fim de Semana Verde", "Realize 2 descartes entre sexta e domingo.", {"action_type": "discard", "weekday": ["fri", "sat", "sun"]}, reward, "discard_count", 2),
        ("Acumule Bins 50", "Acumule 50 Bins com descartes.", {"action_type": "accumulate_points", "points_target": 50}, reward, "accumulate_points", 50),
        ("Estação do E-Waste", "Complete 3 descartes eletrônicos em 7 dias.", {"action_type": "discard", "material_type_id": material_e_id, "within_days": 7}, reward, "discard_specific_material", 3),
        ("Rotina Sustentável", "Faça 1 descarte por dia por 3 dias seguidos.", {"action_type": "discard", "streak_days": 3}, reward, "discard_count", 3),
    ]
    missions = []
    for name, desc, obj, rew, mtype, target in spec:
        m = db.query(Mission).filter(Mission.name == name).first()
        if not m:
            m = Mission(
                name=name,
                description=desc,
                objective=json.dumps(obj),
                reward_points=rew,
                type=mtype,
                is_active=True,
                start_date=now,
                end_date=end,
                target_quantity=target
            )
            db.add(m)
            db.commit()
            db.refresh(m)
        else:
            m.description = desc
            m.objective = json.dumps(obj)
            m.reward_points = rew
            m.type = mtype
            m.is_active = True
            m.start_date = now
            m.end_date = end
            m.target_quantity = target
            db.add(m)
            db.commit()
            db.refresh(m)
        missions.append(m)
    return missions


def ensure_rewards(db):
    print("Garantindo a existência de recompensas...")
    now = datetime.now(UTC)
    rewards_spec = [
        {
            "name": "SUCO DE LARANJA",
            "description": "Vá até o(a) CANTINA, e aproveite para se hidratar, herói!",
            "cost": 250,
            "location": "CANTINA",
            "expires_at": now + timedelta(days=1),
        },
        {
            "name": "FICHA DE SALGADO",
            "description": "Vá até o(a) CANTINA, pois um herói não fica de barriga vazia!",
            "cost": 525,
            "location": "CANTINA",
            "expires_at": now + timedelta(days=1),
        },
        {
            "name": "ECO-BAG",
            "description": "Vá até o(a) DIRETORIA, leve suas necessidades com estilo!",
            "cost": 720,
            "location": "DIRETORIA",
            "expires_at": now + timedelta(days=2),
        },
    ]
    for data in rewards_spec:
        reward = db.query(Reward).filter(Reward.name == data["name"]).first()
        if not reward:
            reward = Reward(**data)
            db.add(reward)
        else:
            reward.description = data["description"]
            reward.cost = data["cost"]
            reward.location = data["location"]
            reward.expires_at = data["expires_at"]
            db.add(reward)
    db.commit()
    print("Recompensas garantidas.")


def assign_all_missions_to_users(db, users, missions):
    for u in users:
        for m in missions:
            um = db.query(UserMission).filter(
                UserMission.user_id == u.id,
                UserMission.mission_id == m.id
            ).first()
            if not um:
                um = UserMission(
                    user_id=u.id,
                    mission_id=m.id,
                    status="in_progress",
                    progress=0,
                    completed_at=None
                )
                db.add(um)
            else:
                um.status = "in_progress"
                um.progress = 0
                um.completed_at = None
                db.add(um)
        db.commit()


def generate_unique_codes(db, material_e_id, material_ne_id, per_type=10):
    db.query(UniqueCode).filter(UniqueCode.is_used == False).delete()
    db.commit()
    codes = {"electronic": [], "non_electronic": []}
    for _ in range(per_type):
        codes["electronic"].append(generate_code(db, material_type_id=material_e_id))
        codes["non_electronic"].append(generate_code(db, material_type_id=material_ne_id))
    return codes


def clear_user_achievements(db, users):
    for u in users:
        db.query(UserAchievement).filter(UserAchievement.user_id == u.id).delete()
    db.commit()



def create_test_data():
    ensure_schema_fresh()
    db = get_db_session()
    try:
        material_e = upsert_material(db, "Eletrônico", 25.0)
        material_ne = upsert_material(db, "Não Eletrônico", 10.0)

        users = ensure_users(db)
        ensure_achievements(db, material_e.id)
        missions = ensure_missions(db, material_e.id, material_ne.id)
        ensure_rewards(db)
        assign_all_missions_to_users(db, users, missions)
        clear_user_achievements(db, users)

        codes = generate_unique_codes(db, material_e.id, material_ne.id, per_type=12)

        print("\n" + "=" * 50)
        print("Códigos únicos gerados para teste:")
        print(json.dumps(codes, ensure_ascii=False, indent=2))
        print("=" * 50 + "\n")
        print("Seed concluído com sucesso.")
    except Exception as e:
        db.rollback()
        print(f"Erro durante o seed: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()


if __name__ == "__main__":
    create_test_data()
