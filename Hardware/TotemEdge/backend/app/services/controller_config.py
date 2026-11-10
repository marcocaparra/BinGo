"""Shared C configuration; Python validates it without enabling physical dispatch."""

from pathlib import Path
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator


# 10 s of commanded waits + 20 s for initial readback, SQLite, sysfs,
# scheduling and IPC. This is a command budget, never mechanical evidence.
JOINT_COMMAND_TIMEOUT_SECONDS = 30.0


class _SettingsModel(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)


class ConfiguredHatch(_SettingsModel):
    """Sides are viewed from the Totem's front; JSON supplies the physical map.

    A tested Linux chip/channel does not establish an electrical RX/TX identity.
    """

    intended_signal: Literal["RX", "TX"] | None = None
    closed_degrees: int | None = Field(default=None, ge=0, le=180)
    open_degrees: int | None = Field(default=None, ge=0, le=180)
    pwm_chip: int | None = Field(default=None, ge=0)
    pwm_channel: int | None = Field(default=None, ge=0)
    closed_pulse_ns: int | None = Field(default=None, gt=0)
    open_pulse_ns: int | None = Field(default=None, gt=0)


class HatchWiring(ConfiguredHatch):
    connector_pin: str | None = Field(default=None, min_length=1)
    soc_pad: str | None = Field(default=None, min_length=1)


class ConfiguredMapping(_SettingsModel):
    right: ConfiguredHatch
    left: ConfiguredHatch


class JointCyclePolicy(_SettingsModel):
    """joint-v1 timing is a command policy, never proof of motion or drop."""

    mode: Literal["joint-v1"]
    hold_open_ms: int
    hold_start: Literal["after_both_open_commands"]
    hold_clock: Literal["monotonic"]
    completion_policy: Literal["operational-sequence-v1"] | None = None
    close_settle_ms: int | None = None
    initial_condition: Literal["closed_pwm_readback"] | None = None

    @model_validator(mode="after")
    def approved_duration(self) -> Self:
        if self.hold_open_ms != 5000:
            raise ValueError("joint-v1 exige permanência de 5000 ms.")
        if self.completion_policy is not None:
            if self.close_settle_ms != 5000 or self.initial_condition is None:
                raise ValueError("Conclusão operacional exige estabilização de 5000 ms e condição inicial explícita.")
        elif self.close_settle_ms is not None or self.initial_condition is not None:
            raise ValueError("Estabilização e condição inicial exigem política de conclusão explícita.")
        return self


class PhysicalConfigDiagnostic(_SettingsModel):
    protocol: Literal["bingo-pwm-config-v1"]
    configuration: Literal["INCOMPLETE", "DECLARED"]
    execution_ready: Literal[False]
    completion_provider: Literal[False]
    stop_policy: Literal[False]
    mapping: ConfiguredMapping
    period_ns: int | None = Field(ge=1)
    polarity: Literal["normal", "inversed"] | None
    cycle_plan: tuple[str, ...]
    cycle_policy: JointCyclePolicy | None = None
    c_executor_configured: bool = False


class CycleDeclarations(_SettingsModel):
    # Missing mode preserves the original sequential/empty contract verbatim.
    mode: Literal["joint-v1"] | None = None
    hold_open_ms: int | None = None
    hold_start: Literal["after_both_open_commands"] | None = None
    hold_clock: Literal["monotonic"] | None = None
    completion_policy: Literal["operational-sequence-v1"] | None = None
    close_settle_ms: int | None = None
    initial_condition: Literal["closed_pwm_readback"] | None = None
    open_order: Literal["left_then_right", "right_then_left"] | None = None
    close_order: Literal["left_then_right", "right_then_left"] | None = None
    drop_reference: str | None = Field(default=None, min_length=1)
    homologation_reference: str | None = Field(default=None, min_length=1)

    @model_validator(mode="after")
    def unambiguous_policy(self) -> Self:
        if self.mode is not None:
            if self.open_order is not None or self.close_order is not None:
                raise ValueError("Modo conjunto não aceita ordem sequencial.")
            self.joint_policy()
        elif any(
            value is not None
            for value in (
                self.hold_open_ms, self.hold_start, self.hold_clock,
                self.completion_policy, self.close_settle_ms, self.initial_condition,
            )
        ):
            raise ValueError("Permanência explícita exige modo joint-v1.")
        return self

    def joint_policy(self) -> JointCyclePolicy | None:
        if self.mode is None:
            return None
        return JointCyclePolicy.model_validate(
            {
                "mode": self.mode,
                "hold_open_ms": self.hold_open_ms,
                "hold_start": self.hold_start,
                "hold_clock": self.hold_clock,
                "completion_policy": self.completion_policy,
                "close_settle_ms": self.close_settle_ms,
                "initial_condition": self.initial_condition,
            }
        )

    def configured(self) -> bool:
        if self.mode is not None:
            return self.joint_policy() is not None
        return all(
            (
                self.open_order,
                self.close_order,
                self.drop_reference,
                self.homologation_reference,
            )
        )

    def plan(self) -> tuple[str, ...]:
        if not self.configured():
            return ()
        if self.mode is not None:
            return (
                "REQUIRE_CLOSED_PWM" if self.completion_policy else "REQUIRE_INITIAL_CLOSED",
                "OPEN_BOTH",
                "HOLD_OPEN",
                "CLOSE_BOTH",
                "SETTLE_CLOSED" if self.completion_policy else "AWAIT_INITIAL_EVIDENCE",
            )
        opening = (
            ("OPEN_LEFT", "OPEN_RIGHT")
            if self.open_order == "left_then_right"
            else ("OPEN_RIGHT", "OPEN_LEFT")
        )
        closing = (
            ("CLOSE_LEFT", "CLOSE_RIGHT")
            if self.close_order == "left_then_right"
            else ("CLOSE_RIGHT", "CLOSE_LEFT")
        )
        return (
            *opening,
            "AWAIT_OPEN_EVIDENCE",
            "AWAIT_DROP_EVIDENCE",
            *closing,
            "AWAIT_INITIAL_EVIDENCE",
        )


class PhysicalDeclarations(_SettingsModel):
    # Keys are mechanical sides. No PWM3/4 -> Linux number conversion exists.
    right: HatchWiring = Field(default_factory=HatchWiring)
    left: HatchWiring = Field(default_factory=HatchWiring)
    period_ns: int | None = Field(default=None, gt=0)
    polarity: Literal["normal", "inversed"] | None = None
    mapping_reference: str | None = Field(default=None, min_length=1)
    calibration_reference: str | None = Field(default=None, min_length=1)
    completion_reference: str | None = Field(default=None, min_length=1)
    safety_recovery_reference: str | None = Field(default=None, min_length=1)
    cycle: CycleDeclarations = Field(default_factory=CycleDeclarations)

    def diagnostic_mapping(self) -> ConfiguredMapping:
        return ConfiguredMapping(
            **{
                side: ConfiguredHatch.model_validate(
                    getattr(self, side).model_dump(exclude={"connector_pin", "soc_pad"})
                )
                for side in ("right", "left")
            }
        )

    @model_validator(mode="after")
    def consistent(self) -> Self:
        if (
            self.right.pwm_chip is not None
            and self.right.pwm_channel is not None
            and (self.right.pwm_chip, self.right.pwm_channel)
            == (self.left.pwm_chip, self.left.pwm_channel)
        ):
            raise ValueError("Escotilhas não podem compartilhar o mesmo PWM Linux.")
        for hatch in (self.right, self.left):
            for pulse in (hatch.closed_pulse_ns, hatch.open_pulse_ns):
                if self.period_ns is not None and pulse is not None:
                    if pulse >= self.period_ns:
                        raise ValueError("Pulso deve ser menor que o período.")
        return self

    def blockers(self) -> tuple[str, ...]:
        blockers = []
        hatches = (self.right, self.left)
        if not self.mapping_reference or any(
            any(
                getattr(h, field) is None
                for field in ("connector_pin", "soc_pad", "pwm_chip", "pwm_channel")
            )
            for h in hatches
        ):
            blockers.append("PWM_MAPPING_UNVERIFIED")
        if (
            not self.calibration_reference
            or self.period_ns is None
            or self.polarity is None
            or any(
                h.closed_pulse_ns is None or h.open_pulse_ns is None for h in hatches
            )
        ):
            blockers.append("PULSE_CALIBRATION_UNVERIFIED")
        if not self.safety_recovery_reference:
            blockers.append("SAFETY_RECOVERY_UNVERIFIED")
        if not self.completion_reference:
            blockers.append("MOTION_CONFIRMATION_UNDEFINED")
        return tuple(blockers)

    def c_executor_configured(self) -> bool:
        """Command-state admission for C only; no measured position provider."""
        return bool(
            self.cycle.completion_policy == "operational-sequence-v1"
            and self.mapping_reference
            and self.calibration_reference
            and self.completion_reference
            and self.cycle.homologation_reference
            and self.period_ns is not None
            and self.polarity is not None
            and all(
                all(getattr(h, key) is not None for key in (
                    "pwm_chip", "pwm_channel", "closed_pulse_ns", "open_pulse_ns",
                ))
                for h in (self.right, self.left)
            )
        )


class CControllerSettings(_SettingsModel):
    schema_version: Literal["bingo-c-controller-v1"] = Field(alias="schema")
    executable: Path
    journal: Path
    profile: Literal["doorless-v1"]
    io_timeout_seconds: float = Field(default=2.0, gt=0, le=60, allow_inf_nan=False)
    physical: PhysicalDeclarations = Field(default_factory=PhysicalDeclarations)

    @model_validator(mode="after")
    def absolute_paths(self) -> Self:
        if not self.executable.is_absolute() or not self.journal.is_absolute():
            raise ValueError("Executable e journal exigem caminhos absolutos.")
        return self

    @classmethod
    def from_file(cls, path: Path, *, backend_journal: Path | None = None):
        if not path.is_absolute():
            raise ValueError("Configuração exige caminho absoluto.")
        with path.open("rb") as stream:
            raw = stream.read(16385)
        if len(raw) > 16384:
            raise ValueError("Configuração C excede 16 KiB.")
        settings = cls.model_validate_json(raw)
        if backend_journal is not None:
            # SQLite sidecars and the retained C lock cannot overlap either.
            suffixes = ("", "-wal", "-shm", "-journal", ".lock")
            python_base = backend_journal.resolve()
            c_base = settings.journal.resolve()
            python_files = [Path(str(python_base) + s).resolve() for s in suffixes]
            c_files = [Path(str(c_base) + s).resolve() for s in suffixes]
            for journal in c_files:
                for other in python_files:
                    if journal == other or (
                        journal.exists() and other.exists() and journal.samefile(other)
                    ):
                        raise ValueError("Journals Python e C devem ser distintos.")
        return settings


class ControllerReadiness(_SettingsModel):
    configuration: Literal["NOT_CONFIGURED", "INVALID", "INCOMPLETE", "DECLARED"]
    transport: Literal["NOT_CONNECTED", "DIAGNOSTIC_OK", "CONNECTED_BLOCKED", "FAILED"]
    execution_ready: Literal[False] = False
    source: Literal["UNAVAILABLE"] = "UNAVAILABLE"
    blockers: tuple[str, ...]
    configured_physical: PhysicalDeclarations | None = None
    cycle_plan: tuple[str, ...] = ()
    cycle_policy: JointCyclePolicy | None = None
    c_executor_configured: bool = False
    physical_command_timeout_seconds: float | None = None
