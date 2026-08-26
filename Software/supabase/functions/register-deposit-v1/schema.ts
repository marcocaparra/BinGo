const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ALLOWED_FIELDS = new Set([
  "event_id",
  "class_id",
  "student_id",
  "is_valid",
  "detected_type",
  "waste_category_code",
  "category_source",
]);

const WASTE_CATEGORY_CODES = new Set([
  "BATTERY",
  "MOBILE_DEVICE",
  "CABLE_WIRE",
  "PERIPHERAL",
  "OTHER_EWASTE",
  "UNKNOWN",
]);

const IDENTIFIED_CATEGORY_SOURCES = new Set([
  "AI_CONFIRMED",
  "USER_CORRECTED",
]);

export type DepositRequestBody = Readonly<{
  event_id: string;
  class_id: string;
  student_id: string | null;
  is_valid: boolean;
  detected_type: string | null;
  waste_category_code: string | null;
  category_source: string | null;
}>;

const INVALID_OPTIONAL_VALUE = Symbol("INVALID_OPTIONAL_VALUE");

function optionalStringOrNull(
  object: Record<string, unknown>,
  field: string,
): string | null | typeof INVALID_OPTIONAL_VALUE {
  const value = object[field];
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value === "string") {
    return value;
  }
  return INVALID_OPTIONAL_VALUE;
}

export function parseDepositRequestBody(
  value: unknown,
): DepositRequestBody | null {
  if (
    typeof value !== "object" || value === null || Array.isArray(value)
  ) {
    return null;
  }

  const object = value as Record<string, unknown>;
  if (Object.keys(object).some((field) => !ALLOWED_FIELDS.has(field))) {
    return null;
  }

  if (
    typeof object.event_id !== "string" ||
    !UUID_PATTERN.test(object.event_id) ||
    typeof object.class_id !== "string" ||
    !UUID_PATTERN.test(object.class_id) ||
    typeof object.is_valid !== "boolean"
  ) {
    return null;
  }

  const studentId = optionalStringOrNull(object, "student_id");
  const detectedType = optionalStringOrNull(object, "detected_type");
  const categoryCode = optionalStringOrNull(object, "waste_category_code");
  const categorySource = optionalStringOrNull(object, "category_source");

  if (
    studentId === INVALID_OPTIONAL_VALUE ||
    detectedType === INVALID_OPTIONAL_VALUE ||
    categoryCode === INVALID_OPTIONAL_VALUE ||
    categorySource === INVALID_OPTIONAL_VALUE ||
    (studentId !== null && !UUID_PATTERN.test(studentId))
  ) {
    return null;
  }

  if (object.is_valid) {
    if (
      categoryCode === null || categorySource === null ||
      !WASTE_CATEGORY_CODES.has(categoryCode)
    ) {
      return null;
    }

    const categoryCombinationIsValid = categoryCode === "UNKNOWN"
      ? categorySource === "UNIDENTIFIED"
      : IDENTIFIED_CATEGORY_SOURCES.has(categorySource);
    if (!categoryCombinationIsValid) {
      return null;
    }
  } else if (categoryCode !== null || categorySource !== null) {
    return null;
  }

  return Object.freeze({
    event_id: object.event_id,
    class_id: object.class_id,
    student_id: studentId,
    is_valid: object.is_valid,
    detected_type: detectedType,
    waste_category_code: categoryCode,
    category_source: categorySource,
  });
}
