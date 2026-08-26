from enum import Enum


class StudentStatus(str, Enum):
    ACTIVE = "ACTIVE"
    INACTIVE = "INACTIVE"


class AdminRole(str, Enum):
    ADMIN = "ADMIN"
    ADMIN_CONQUISTA = "ADMIN_CONQUISTA"
    BINGO_ADMIN = "BINGO_ADMIN"


class MachineStatus(str, Enum):
    ONLINE = "ONLINE"
    OFFLINE = "OFFLINE"
    MAINTENANCE = "MAINTENANCE"
    OUT_OF_SERVICE = "OUT_OF_SERVICE"


class RewardStatus(str, Enum):
    AVAILABLE = "AVAILABLE"
    DISABLED = "DISABLED"
    OUT_OF_STOCK = "OUT_OF_STOCK"


class DepositCategorySource(str, Enum):
    AI_CONFIRMED = "AI_CONFIRMED"
    USER_CORRECTED = "USER_CORRECTED"
    UNIDENTIFIED = "UNIDENTIFIED"


class WasteCategoryCode(str, Enum):
    BATTERY = "BATTERY"
    MOBILE_DEVICE = "MOBILE_DEVICE"
    CABLE_WIRE = "CABLE_WIRE"
    PERIPHERAL = "PERIPHERAL"
    OTHER_EWASTE = "OTHER_EWASTE"
    UNKNOWN = "UNKNOWN"


class RedemptionStatus(str, Enum):
    PENDING = "PENDING"
    DELIVERED = "DELIVERED"
    CANCELED = "CANCELED"
    EXPIRED = "EXPIRED"


class ActorType(str, Enum):
    ADMIN = "ADMIN"
    STUDENT = "STUDENT"
    MACHINE = "MACHINE"
    SYSTEM = "SYSTEM"


class PrincipalType(str, Enum):
    STUDENT = "student"
    ADMIN_SCHOOL = "admin_school"
    BINGO_ADMIN = "bingo_admin"
    EDGE_SERVICE = "edge_service"
