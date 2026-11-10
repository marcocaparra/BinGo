"""Explicit local C configuration. Declarations never authorize physical motion."""

from pathlib import Path
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator


class _SettingsModel(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid", strict=True)


class ConfiguredHatch(_SettingsModel):
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


class CycleDeclarations(_SettingsModel):
    open_order: Literal["left_then_right", "right_then_left"] | None = None
    close_order: Literal["left_then_right", "right_then_left"] | None = None
    drop_reference: str | None = Field(default=None, min_length=1)
    homologation_reference: str | None = Field(default=None, min_length=1)

    def configured(self) -> bool:
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
