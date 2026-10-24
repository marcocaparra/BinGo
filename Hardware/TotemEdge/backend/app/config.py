import math
import os
import re
from dataclasses import dataclass, field
from typing import Literal
from urllib.parse import urlsplit

ConfigurationOutcome = Literal["NOT_CONFIGURED", "INVALID_CONFIGURATION"]


class SupabaseConfigurationError(ValueError):
    def __init__(self, outcome: ConfigurationOutcome):
        super().__init__("Configuração do backend central ausente ou inválida.")
        self.outcome = outcome


@dataclass(frozen=True)
class SupabaseSettings:
    base_url: str = field(repr=False)
    machine_id: str = field(repr=False)
    machine_api_key: str = field(repr=False)
    timeout_seconds: float = 5.0

    def __post_init__(self) -> None:
        if not self.base_url or not self.machine_id or not self.machine_api_key:
            raise SupabaseConfigurationError("NOT_CONFIGURED")
        try:
            parsed = urlsplit(self.base_url)
            valid_url = (
                all(32 < ord(char) < 127 for char in self.base_url)
                and "?" not in self.base_url
                and "#" not in self.base_url
                and parsed.hostname is not None
                and parsed.username is None
                and parsed.password is None
                and parsed.path in ("", "/")
                and (parsed.port is None or 1 <= parsed.port <= 65535)
                and (
                    parsed.scheme == "https"
                    or parsed.scheme == "http"
                    and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
                )
            )
        except ValueError:
            valid_url = False
        valid_machine_id = re.fullmatch(
            r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
            r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            self.machine_id,
        )
        if (
            not valid_url
            or not valid_machine_id
            or not all(32 <= ord(char) < 127 for char in self.machine_api_key)
            or not math.isfinite(self.timeout_seconds)
            or self.timeout_seconds <= 0
        ):
            raise SupabaseConfigurationError("INVALID_CONFIGURATION")

    @classmethod
    def from_environment(cls) -> "SupabaseSettings":
        try:
            timeout = float(os.getenv("BINGO_BACKEND_TIMEOUT_SECONDS", "5"))
        except ValueError:
            raise SupabaseConfigurationError("INVALID_CONFIGURATION") from None
        return cls(
            base_url=os.getenv("BINGO_SUPABASE_URL", ""),
            machine_id=os.getenv("BINGO_MACHINE_ID", ""),
            machine_api_key=os.getenv("BINGO_MACHINE_API_KEY", ""),
            timeout_seconds=timeout,
        )
