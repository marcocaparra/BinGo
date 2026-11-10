#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* stdout is reserved for the local protocol; legacy diagnostics stay on stderr. */
#define printf(...) fprintf(stderr, __VA_ARGS__)

#include "bingo_physical.inc"
#include "bingo_pwm.inc"

#ifdef BINGO_PWM_SIMULATED
static int simulated_writes = 0;
static int simulated_fail_after = -1;
#endif

/* Historical dafc9ab values ONLY. Active physical mapping comes from JSON;
 * these nominal pulses must never configure the current assembly.
 * Physical startup remains blocked in bingo_inicializar and the IPC entrypoint.
 */
#define PWM_CHIP 0
#define PWM_PERIOD_NS 20000000L
#define SERVO_0_GRAUS_NS 500000L
#define SERVO_90_GRAUS_NS 1500000L
#define SERVO_180_GRAUS_NS 2500000L
#define TEMPO_QUEDA_SEGUNDOS 6

#define PWM_PORTA_ESQUERDA 1
#define PWM_PORTA_DIREITA 2
#define PWM_ESCOTILHA_ESQUERDA 3
#define PWM_ESCOTILHA_DIREITA 4

#define PORTA_ESQ_ABERTA_NS SERVO_0_GRAUS_NS
#define PORTA_ESQ_FECHADA_NS SERVO_90_GRAUS_NS
#define PORTA_DIR_ABERTA_NS SERVO_180_GRAUS_NS
#define PORTA_DIR_FECHADA_NS SERVO_90_GRAUS_NS

#define ESCOTILHA_ESQ_FECHADA_NS SERVO_90_GRAUS_NS
#define ESCOTILHA_ESQ_ABERTA_NS SERVO_0_GRAUS_NS
#define ESCOTILHA_DIR_FECHADA_NS SERVO_90_GRAUS_NS
#define ESCOTILHA_DIR_ABERTA_NS SERVO_180_GRAUS_NS

#ifdef BINGO_PWM_SIMULATED
/* Doorless laboratory v1: logical labels, NOT sysfs indices or SoC pins.
 * Manual angle references only. No angle-to-pulse conversion is authorized.
 * Keep the legacy routines above unchanged for historical laboratory commands.
 */
/* Retained laboratory v1 identity: never reinterpret its journal/calibration.
 * Physical orientation is viewed from the FRONT: JSON RIGHT=chip0/channel3,
 * LEFT=chip0/channel4 (reported hardware tests 2026-11-10). These laboratory
 * labels are not used to derive the physical mapping or RX/TX wiring.
 */
#define LAB_RIGHT_PWM_LABEL 3
#define LAB_LEFT_PWM_LABEL 4
#define LAB_RIGHT_CLOSED_DEG HATCH_RIGHT_CLOSED_DEG
#define LAB_RIGHT_OPEN_DEG HATCH_RIGHT_OPEN_DEG
#define LAB_LEFT_CLOSED_DEG HATCH_LEFT_CLOSED_DEG
#define LAB_LEFT_OPEN_DEG HATCH_LEFT_OPEN_DEG
#define LAB_DROP_INTERVAL_MS 6000UL

static int simulated_hatch_pose(const char *side, int label, int angle,
                                unsigned long tick_ms)
{
    if (simulated_fail_after >= 0 && simulated_writes >= simulated_fail_after)
        return -1;
    simulated_writes++;
    fprintf(stderr, "SIMULATED_PWM %s PWM%d ANGLE_DEG %d TICK_MS %lu\n",
            side, label, angle, tick_ms);
    return 0;
}

static int simulated_doorless_hatch(void)
{
    if (simulated_hatch_pose("RIGHT", LAB_RIGHT_PWM_LABEL, LAB_RIGHT_OPEN_DEG, 0) ||
        simulated_hatch_pose("LEFT", LAB_LEFT_PWM_LABEL, LAB_LEFT_OPEN_DEG, 0))
        return -1;
    /* Virtual time only: this is not a calibrated physical drop delay.
     * --delay-ms remains a separate wall-clock fault injection hook.
     */
    fprintf(stderr, "SIMULATED_DROP_INTERVAL_MS %lu\n", LAB_DROP_INTERVAL_MS);
    return simulated_hatch_pose("RIGHT", LAB_RIGHT_PWM_LABEL, LAB_RIGHT_CLOSED_DEG,
                                LAB_DROP_INTERVAL_MS) ||
           simulated_hatch_pose("LEFT", LAB_LEFT_PWM_LABEL, LAB_LEFT_CLOSED_DEG,
                                LAB_DROP_INTERVAL_MS);
}
#endif

typedef enum {
    RESPOSTA_PENDENTE = 0,
    RESPOSTA_NAO,
    RESPOSTA_SIM
} RespostaExterna;

typedef enum {
    ESTADO_AGUARDAR_INICIAR = 0,
    ESTADO_AGUARDAR_AREA_SEGURA,
    ESTADO_AGUARDAR_CLASSIFICACAO,
    ESTADO_AGUARDAR_CONFIRMACAO,
    ESTADO_AGUARDAR_QUEDA
} EstadoControlador;

static bool toque_tela_iniciar = false;
static RespostaExterna camera_area_segura = RESPOSTA_PENDENTE;
static RespostaExterna camera_item_eletronico = RESPOSTA_PENDENTE;
static RespostaExterna toque_tela_confirmar_item = RESPOSTA_PENDENTE;

static EstadoControlador estado = ESTADO_AGUARDAR_INICIAR;
static struct timespec instante_abertura_escotilha;

static int escrever_texto(const char *caminho, const char *texto)
{
    int fd = open(caminho, O_WRONLY);

    if (fd < 0) {
        fprintf(stderr, "Erro ao abrir %s: %s\n", caminho, strerror(errno));
        return -1;
    }

    size_t tamanho = strlen(texto);
    ssize_t escritos = write(fd, texto, tamanho);

    if (escritos != (ssize_t)tamanho) {
        fprintf(stderr, "Erro ao escrever em %s: %s\n", caminho, strerror(errno));
        close(fd);
        return -1;
    }

    if (close(fd) != 0) {
        fprintf(stderr, "Erro ao fechar %s: %s\n", caminho, strerror(errno));
        return -1;
    }

    return 0;
}

static int escrever_long(const char *caminho, long valor)
{
    char texto[32];
    snprintf(texto, sizeof(texto), "%ld", valor);
    return escrever_texto(caminho, texto);
}

static int ler_long(const char *caminho, long *valor)
{
    FILE *arquivo = fopen(caminho, "r");

    if (arquivo == NULL) {
        return -1;
    }

    int resultado = fscanf(arquivo, "%ld", valor);
    fclose(arquivo);

    return resultado == 1 ? 0 : -1;
}

static void caminho_pwm(char *destino, size_t tamanho, int canal, const char *arquivo)
{
    snprintf(
        destino,
        tamanho,
        "/sys/class/pwm/pwmchip%d/pwm%d/%s",
        PWM_CHIP,
        canal,
        arquivo
    );
}

static int esperar_pwm_aparecer(int canal)
{
    char diretorio[128];

    snprintf(
        diretorio,
        sizeof(diretorio),
        "/sys/class/pwm/pwmchip%d/pwm%d",
        PWM_CHIP,
        canal
    );

    for (int tentativa = 0; tentativa < 40; tentativa++) {
        if (access(diretorio, F_OK) == 0) {
            return 0;
        }

        struct timespec espera = {0, 50000000L};
        nanosleep(&espera, NULL);
    }

    fprintf(stderr, "PWM%d nao apareceu no sysfs.\n", canal);
    return -1;
}

static int exportar_pwm(int canal)
{
    char diretorio[128];
    char caminho_export[128];

    snprintf(
        diretorio,
        sizeof(diretorio),
        "/sys/class/pwm/pwmchip%d/pwm%d",
        PWM_CHIP,
        canal
    );

    if (access(diretorio, F_OK) == 0) {
        return 0;
    }

    snprintf(
        caminho_export,
        sizeof(caminho_export),
        "/sys/class/pwm/pwmchip%d/export",
        PWM_CHIP
    );

    if (escrever_long(caminho_export, canal) != 0) {
        if (errno != EBUSY) {
            return -1;
        }
    }

    return esperar_pwm_aparecer(canal);
}

static int configurar_pwm(int canal)
{
    char caminho[160];
    long habilitado = 0;

    caminho_pwm(caminho, sizeof(caminho), canal, "enable");

    if (ler_long(caminho, &habilitado) == 0) {
        if (habilitado != 0) {
            if (escrever_long(caminho, 0) != 0) {
                return -1;
            }
        }
    }

    caminho_pwm(caminho, sizeof(caminho), canal, "duty_cycle");

    if (escrever_long(caminho, 0) != 0) {
        return -1;
    }

    caminho_pwm(caminho, sizeof(caminho), canal, "period");

    if (escrever_long(caminho, PWM_PERIOD_NS) != 0) {
        return -1;
    }

    caminho_pwm(caminho, sizeof(caminho), canal, "duty_cycle");

    if (escrever_long(caminho, SERVO_90_GRAUS_NS) != 0) {
        return -1;
    }

    caminho_pwm(caminho, sizeof(caminho), canal, "enable");

    if (escrever_long(caminho, 1) != 0) {
        return -1;
    }

    printf("[PWM] Canal %d configurado.\n", canal);

    return 0;
}

static int mover_servo(int canal, long pulso_ns)
{
#ifdef BINGO_PWM_SIMULATED
    if (simulated_fail_after >= 0 && simulated_writes >= simulated_fail_after) {
        return -1;
    }
    simulated_writes++;
    fprintf(stderr, "SIMULATED_PWM %d %ld\n", canal, pulso_ns);
    return 0;
#else
    char caminho[160];

    caminho_pwm(
        caminho,
        sizeof(caminho),
        canal,
        "duty_cycle"
    );

    return escrever_long(caminho, pulso_ns);
#endif
}

static int abrir_porta_superior(void)
{
    printf("[ELETRONICA] Abrindo porta superior.\n");

    if (mover_servo(PWM_PORTA_ESQUERDA, PORTA_ESQ_ABERTA_NS) != 0) {
        return -1;
    }

    if (mover_servo(PWM_PORTA_DIREITA, PORTA_DIR_ABERTA_NS) != 0) {
        return -1;
    }

    return 0;
}

/* Same PWM sequence; authorization is supplied by the backend command layer. */
static int fechar_porta_superior_autorizada(void)
{
    printf("[ELETRONICA] Fechando porta superior.\n");

    if (mover_servo(PWM_PORTA_ESQUERDA, PORTA_ESQ_FECHADA_NS) != 0) {
        return -1;
    }

    if (mover_servo(PWM_PORTA_DIREITA, PORTA_DIR_FECHADA_NS) != 0) {
        return -1;
    }

    return 0;
}

static int fechar_porta_superior(void)
{
    if (camera_area_segura != RESPOSTA_SIM) {
        printf("[SEGURANCA] Fechamento bloqueado.\n");
        return 1;
    }
    return fechar_porta_superior_autorizada();
}

static int abrir_escotilha(void)
{
    printf("[ELETRONICA] Abrindo escotilha.\n");

    if (mover_servo(PWM_ESCOTILHA_ESQUERDA, ESCOTILHA_ESQ_ABERTA_NS) != 0) {
        return -1;
    }

    if (mover_servo(PWM_ESCOTILHA_DIREITA, ESCOTILHA_DIR_ABERTA_NS) != 0) {
        return -1;
    }

    return 0;
}

static int fechar_escotilha(void)
{
    printf("[ELETRONICA] Fechando escotilha.\n");

    if (mover_servo(PWM_ESCOTILHA_ESQUERDA, ESCOTILHA_ESQ_FECHADA_NS) != 0) {
        return -1;
    }

    if (mover_servo(PWM_ESCOTILHA_DIREITA, ESCOTILHA_DIR_FECHADA_NS) != 0) {
        return -1;
    }

    return 0;
}

static void resetar_entradas_externas(void)
{
    toque_tela_iniciar = false;
    camera_area_segura = RESPOSTA_PENDENTE;
    camera_item_eletronico = RESPOSTA_PENDENTE;
    toque_tela_confirmar_item = RESPOSTA_PENDENTE;
}

static void retornar_estado_inicial(void)
{
    resetar_entradas_externas();
    estado = ESTADO_AGUARDAR_INICIAR;
    printf("[BinGo] Aguardando TOQUE_TELA_INICIAR.\n");
}

static int estado_inicial_fisico(void)
{
    if (abrir_porta_superior() != 0) {
        return -1;
    }

    if (fechar_escotilha() != 0) {
        return -1;
    }

    retornar_estado_inicial();
    return 0;
}

static bool passaram_seis_segundos(void)
{
    struct timespec agora;

    clock_gettime(CLOCK_MONOTONIC, &agora);

    time_t segundos =
        agora.tv_sec -
        instante_abertura_escotilha.tv_sec;

    return segundos >= TEMPO_QUEDA_SEGUNDOS;
}

void bingo_evento_toque_iniciar(void)
{
    toque_tela_iniciar = true;
}

void bingo_evento_area_segura(bool segura)
{
    camera_area_segura =
        segura ? RESPOSTA_SIM : RESPOSTA_NAO;
}

void bingo_evento_classificacao_item(bool eletronico)
{
    camera_item_eletronico =
        eletronico ? RESPOSTA_SIM : RESPOSTA_NAO;
}

void bingo_evento_confirmacao_item(bool confirmado)
{
    toque_tela_confirmar_item =
        confirmado ? RESPOSTA_SIM : RESPOSTA_NAO;
}

int bingo_processar(void)
{
    switch (estado) {
        case ESTADO_AGUARDAR_INICIAR:

            if (!toque_tela_iniciar) {
                return 0;
            }

            printf("[INTEGRACAO] TOQUE_TELA_INICIAR recebido.\n");

            camera_area_segura = RESPOSTA_PENDENTE;
            estado = ESTADO_AGUARDAR_AREA_SEGURA;

            return 0;

        case ESTADO_AGUARDAR_AREA_SEGURA:

            if (camera_area_segura == RESPOSTA_PENDENTE) {
                return 0;
            }

            if (camera_area_segura == RESPOSTA_NAO) {
                printf("[SEGURANCA] Area insegura. Porta permanece aberta.\n");
                camera_area_segura = RESPOSTA_PENDENTE;
                return 0;
            }

            if (fechar_porta_superior() != 0) {
                return -1;
            }

            camera_item_eletronico = RESPOSTA_PENDENTE;
            estado = ESTADO_AGUARDAR_CLASSIFICACAO;

            return 0;

        case ESTADO_AGUARDAR_CLASSIFICACAO:

            if (camera_item_eletronico == RESPOSTA_PENDENTE) {
                return 0;
            }

            if (camera_item_eletronico == RESPOSTA_NAO) {
                printf("[INTEGRACAO] Item nao eletronico.\n");

                if (
                    fechar_escotilha() != 0 ||
                    abrir_porta_superior() != 0
                ) {
                    return -1;
                }

                retornar_estado_inicial();
                return 0;
            }

            printf("[INTEGRACAO] Aguardando confirmacao do item.\n");

            toque_tela_confirmar_item = RESPOSTA_PENDENTE;
            estado = ESTADO_AGUARDAR_CONFIRMACAO;

            return 0;

        case ESTADO_AGUARDAR_CONFIRMACAO:

            if (toque_tela_confirmar_item == RESPOSTA_PENDENTE) {
                return 0;
            }

            if (toque_tela_confirmar_item == RESPOSTA_NAO) {
                printf("[INTEGRACAO] Item nao confirmado.\n");

                if (
                    fechar_escotilha() != 0 ||
                    abrir_porta_superior() != 0
                ) {
                    return -1;
                }

                retornar_estado_inicial();
                return 0;
            }

            if (abrir_escotilha() != 0) {
                return -1;
            }

            clock_gettime(
                CLOCK_MONOTONIC,
                &instante_abertura_escotilha
            );

            estado = ESTADO_AGUARDAR_QUEDA;

            return 0;

        case ESTADO_AGUARDAR_QUEDA:

            if (!passaram_seis_segundos()) {
                return 0;
            }

            if (
                fechar_escotilha() != 0 ||
                abrir_porta_superior() != 0
            ) {
                return -1;
            }

            printf("[INTEGRACAO] TELA_DESCARTE_CONCLUIDO.\n");

            retornar_estado_inicial();

            return 0;
    }

    return -1;
}

int bingo_inicializar(void)
{
    /* Startup must never assume a safe position or energize a channel. */
    fprintf(stderr, "Inicializacao fisica bloqueada: homologacao pendente.\n");
    return -1;
}

/* Preserved for review/calibration; deliberately unreachable from the entrypoint. */
static int inicializacao_pwm_legada_nao_homologada(void)
{
    const int canais[] = {
        PWM_PORTA_ESQUERDA,
        PWM_PORTA_DIREITA,
        PWM_ESCOTILHA_ESQUERDA,
        PWM_ESCOTILHA_DIREITA
    };

    if (geteuid() != 0) {
        fprintf(stderr, "Execute este programa com sudo.\n");
        return -1;
    }

    for (
        size_t i = 0;
        i < sizeof(canais) / sizeof(canais[0]);
        i++
    ) {
        if (exportar_pwm(canais[i]) != 0) {
            return -1;
        }
    }

    for (
        size_t i = 0;
        i < sizeof(canais) / sizeof(canais[0]);
        i++
    ) {
        if (configurar_pwm(canais[i]) != 0) {
            return -1;
        }
    }

    return estado_inicial_fisico();
}

static int executar_teste_automatico(void)
{
    printf("\n=== TESTE AUTOMATICO DA ELETRONICA ===\n");

    sleep(2);

    printf("[TESTE] Simulando TOQUE_TELA_INICIAR.\n");
    bingo_evento_toque_iniciar();
    bingo_processar();

    sleep(2);

    printf("[TESTE] Simulando CAMERA_AREA_SEGURA = SIM.\n");
    bingo_evento_area_segura(true);
    bingo_processar();

    sleep(2);

    printf("[TESTE] Simulando ITEM_ELETRONICO = SIM.\n");
    bingo_evento_classificacao_item(true);
    bingo_processar();

    sleep(2);

    printf("[TESTE] Simulando CONFIRMACAO_ITEM = SIM.\n");
    bingo_evento_confirmacao_item(true);
    bingo_processar();

    while (estado == ESTADO_AGUARDAR_QUEDA) {
        if (bingo_processar() != 0) {
            return -1;
        }

        struct timespec ciclo = {0, 100000000L};
        nanosleep(&ciclo, NULL);
    }

    printf("=== TESTE AUTOMATICO CONCLUIDO ===\n");

    return 0;
}

static int demonstracao_legada_nao_homologada(int argc, char *argv[])
{
    printf("BinGo - Modulo eletronico Orange Pi\n");

    if (bingo_inicializar() != 0) {
        fprintf(stderr, "Falha na inicializacao da eletronica.\n");
        return EXIT_FAILURE;
    }

    if (
        argc >= 2 &&
        strcmp(argv[1], "--teste") == 0
    ) {
        if (executar_teste_automatico() != 0) {
            return EXIT_FAILURE;
        }

        return EXIT_SUCCESS;
    }

    while (true) {
        if (bingo_processar() != 0) {
            fprintf(stderr, "Falha no controlador eletronico.\n");
            return EXIT_FAILURE;
        }

        struct timespec ciclo = {0, 100000000L};
        nanosleep(&ciclo, NULL);
    }

    return EXIT_SUCCESS;
}

/* Local reception/result layer. It never invokes the legacy business loop. */
#include "bingo_ipc.inc"
