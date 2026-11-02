"""Somente smoke: Functions TLS sintéticas e sentinela econômica, sem Supabase."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import ssl

MACHINE, SCHOOL, CLASS, STUDENT = [
    f"00000000-0000-4000-8000-{i:012d}" for i in range(1, 5)
]
STATE = {"calls": [], "deposits": 0, "student_balance": 800, "class_xp": 1900}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, body, status=200):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/_probe":
            return self.answer(STATE)
        self.operation()

    def do_POST(self):
        self.operation()

    def operation(self):
        STATE["calls"].append({"method": self.command, "path": self.path})
        if (
            self.headers.get("X-Machine-Id") != MACHINE
            or self.headers.get("X-Api-Key") != "synthetic-machine-credential-only"
        ):
            return self.answer(
                {"error": {"code": "MACHINE_AUTHENTICATION_FAILED"}}, 401
            )
        if self.path == "/functions/v1/register-deposit-v1" or self.path.startswith(
            "/rest/"
        ):
            STATE["deposits"] += 1
            STATE["student_balance"] += 800
            STATE["class_xp"] += 1900
            return self.answer({"unexpected_economic_call": True}, 500)
        if self.path == "/functions/v1/health-v1" and self.command == "GET":
            return self.answer(
                {
                    "status": "AVAILABLE",
                    "can_start_deposit": True,
                    "scope": "CENTRAL_BACKEND",
                    "checked_at": "2026-10-28T12:00:00Z",
                }
            )
        if self.path == "/functions/v1/totem-context-v1" and self.command == "GET":
            return self.answer(
                {
                    "school": {"id": SCHOOL, "name": "Escola sintética"},
                    "machine": {"id": MACHINE, "name": "Máquina de teste"},
                    "classes": [
                        {
                            "id": CLASS,
                            "name": "Turma de teste",
                            "segment": None,
                            "grade": None,
                            "points_class_balance": 1900,
                        }
                    ],
                    "students": [
                        {
                            "id": STUDENT,
                            "name": "Aluno sintético",
                            "class_id": CLASS,
                            "class_name": "Turma de teste",
                            "status": "ACTIVE",
                            "points_student_balance": 800,
                        }
                    ],
                }
            )
        if self.path == "/functions/v1/totem-student-pin-v1" and self.command == "POST":
            body = json.loads(
                self.rfile.read(int(self.headers.get("Content-Length", "0")))
            )
            if body != {"class_id": CLASS, "student_id": STUDENT, "pin": "0012"}:
                return self.answer({"error": {"code": "STUDENT_PIN_INVALID"}}, 401)
            return self.answer(
                {
                    "confirmed": True,
                    "student": {
                        "id": STUDENT,
                        "name": "Aluno sintético",
                        "class_id": CLASS,
                        "class_name": "Turma de teste",
                    },
                }
            )
        self.answer({"error": {"code": "NOT_FOUND"}}, 404)


if __name__ == "__main__":
    # Somente o netns do fixture permite porta baixa sem capabilities no smoke.
    server = ThreadingHTTPServer(("0.0.0.0", 443), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain("/fixture/ca.crt", "/fixture/tls.key")
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
