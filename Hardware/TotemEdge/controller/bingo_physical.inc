/* Angle references only; active mapping comes exclusively from operational JSON.
 * A preflight without configuration cannot report configured channel labels.
 * This describes repository evidence, not a hardware probe or permit.
 */
#define HATCH_RIGHT_CLOSED_DEG 70
#define HATCH_RIGHT_OPEN_DEG 175
#define HATCH_LEFT_CLOSED_DEG 113
#define HATCH_LEFT_OPEN_DEG 5

static int physical_preflight(void)
{
#ifdef BINGO_PWM_SIMULATED
    /* A simulated executable must never advertise physical capabilities. */
    return 2;
#else
    int written = fprintf(stdout,
        "{\"protocol\":\"bingo-physical-preflight-v1\","
        "\"build\":\"PHYSICAL_BLOCKED\",\"ready\":false,"
        "\"source\":\"UNAVAILABLE\",\"physical_confirmed\":false,"
        "\"assembly\":{\"right\":{\"pwm_label\":null,"
        "\"closed_degrees\":%d,\"open_degrees\":%d,"
        "\"sysfs_channel\":null,\"closed_pulse_ns\":null,\"open_pulse_ns\":null},"
        "\"left\":{\"pwm_label\":null,"
        "\"closed_degrees\":%d,\"open_degrees\":%d,"
        "\"sysfs_channel\":null,\"closed_pulse_ns\":null,\"open_pulse_ns\":null}},"
        "\"legacy_evidence\":{\"commit\":\"dafc9ab\","
        "\"sysfs_chip\":0,\"left_channel\":3,\"right_channel\":4,"
        "\"period_ns\":20000000,\"nominal_pulses_ns\":[500000,1500000,2500000],"
        "\"drop_seconds\":6},"
        "\"blockers\":[\"PWM_MAPPING_UNVERIFIED\",\"PULSE_CALIBRATION_UNVERIFIED\","
        "\"SAFETY_RECOVERY_UNVERIFIED\",\"MOTION_CONFIRMATION_UNDEFINED\","
        "\"PHYSICAL_DISPATCH_DISABLED\"]}\n",
        HATCH_RIGHT_CLOSED_DEG, HATCH_RIGHT_OPEN_DEG,
        HATCH_LEFT_CLOSED_DEG, HATCH_LEFT_OPEN_DEG);
    return written < 0 || fflush(stdout) ? 2 : 0;
#endif
}
