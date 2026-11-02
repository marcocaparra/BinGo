"""Public synthetic data shared by tests and the browser fixture; no test runner imports."""

from uuid import UUID

MACHINE, SCHOOL, CLASS, STUDENT = [
    UUID(f"00000000-0000-4000-8000-{i:012d}") for i in range(1, 5)
]
CONTEXT = {
    "school": {"id": str(SCHOOL), "name": "Escola sintética"},
    "machine": {"id": str(MACHINE), "name": "Máquina de teste"},
    "classes": [
        {
            "id": str(CLASS),
            "name": "Turma de teste",
            "segment": None,
            "grade": None,
            "points_class_balance": 1900,
        }
    ],
    "students": [
        {
            "id": str(STUDENT),
            "name": "Aluno sintético",
            "class_id": str(CLASS),
            "class_name": "Turma de teste",
            "status": "ACTIVE",
            "points_student_balance": 800,
        }
    ],
}
PIN = {"class_id": str(CLASS), "student_id": str(STUDENT), "pin": "0012"}
BASE = "/local/simulation/sessions"
KEY = "synthetic-machine-credential-only"
