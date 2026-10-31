#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/*
 * BinGo - Modulo eletronico do totem
 * Controle de 4 servomotores via PWM de hardware do Orange Pi Zero 3.
 *
 * Escopo deste arquivo:
 *   - Porta superior esquerda/direita
 *   - Escotilha inferior esquerda/direita
 *   - Regra logica que impede fechar a porta sem area segura
 *
 * Fora deste arquivo (integracao externa):
 *   - Touchscreen
 *   - Camera / visao computacional
 *   - Backend / pontuacao / banco de dados
 *   - LED (alimentacao fixa, sem controle por software)
 *
 * Calibracao nominal adotada para MG995:
 *   - 50 Hz (periodo de 20 ms)
 *   - 0,5 ms ~ 0 graus
 *   - 1,5 ms ~ 90 graus
 *   - 2,5 ms ~ 180 graus
 *
 * Esses valores sao defaults nominais. A geometria mecanica real do BinGo
 * pode exigir ajuste posterior sem alterar a logica do controlador.
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

/*
 * Defaults nominais para movimentos de aproximadamente 90 graus.
 * Servos do lado direito usam sentido espelhado.
 */
#define PORTA_ESQ_ABERTA_NS SERVO_0_GRAUS_NS
#define PORTA_ESQ_FECHADA_NS SERVO_90_GRAUS_NS
#define PORTA_DIR_ABERTA_NS SERVO_180_GRAUS_NS
#define PORTA_DIR_FECHADA_NS SERVO_90_GRAUS_NS

#define ESCOTILHA_ESQ_FECHADA_NS SERVO_90_GRAUS_NS
#define ESCOTILHA_ESQ_ABERTA_NS SERVO_0_GRAUS_NS
#define ESCOTILHA_DIR_FECHADA_NS SERVO_90_GRAUS_NS
#define ESCOTILHA_DIR_ABERTA_NS SERVO_180_GRAUS_NS

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

/* Pontos de integracao preenchidos por touchscreen/visao no sistema final. */
static bool toque_tela_iniciar = false;
static RespostaExterna camera_area_segura = RESPOSTA_PENDENTE;
static RespostaExterna camera_item_eletronico = RESPOSTA_PENDENTE;
static RespostaExterna toque_tela_confirmar_item = RESPOSTA_PENDENTE;

static EstadoControlador estado = ESTADO_AGUARDAR_INICIAR;
static struct timespec instante_abertura_escotilha;

static int escrever_long(const char *caminho, long valor)
{
    FILE *arquivo = fopen(caminho, "w");
    if (arquivo == NULL) {
        fprintf(stderr, "Erro ao abrir %s: %s\n", caminho, strerror(errno));
        return -1;
    }

    if (fprintf(arquivo, "%ld", valor) < 0) {
        fprintf(stderr, "Erro ao escrever em %s: %s\n", caminho, strerror(errno));
        fclose(arquivo);
        return -1;
    }

    if (fclose(arquivo) != 0) {
        fprintf(stderr, "Erro ao fechar %s: %s\n", caminho, strerror(errno));
        return -1;
    }

    return 0;
}

static void caminho_pwm(char *destino, size_t tamanho, int canal, const char *arquivo)
{
    snprintf(destino, tamanho, "/sys/class/pwm/pwmchip%d/pwm%d/%s", PWM_CHIP, canal, arquivo);
}

static int exportar_pwm(int canal)
{
    char diretorio[128];
    char export_path[128];

    snprintf(diretorio, sizeof(diretorio), "/sys/class/pwm/pwmchip%d/pwm%d", PWM_CHIP, canal);
    if (access(diretorio, F_OK) == 0) {
        return 0;
    }

    snprintf(export_path, sizeof(export_path), "/sys/class/pwm/pwmchip%d/export", PWM_CHIP);
    return escrever_long(export_path, canal);
}

static int configurar_pwm(int canal)
{
    char caminho[160];

    caminho_pwm(caminho, sizeof(caminho), canal, "enable");
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
    return escrever_long(caminho, 1);
}

static int mover_servo(int canal, long pulso_ns)
{
    char caminho[160];
    caminho_pwm(caminho, sizeof(caminho), canal, "duty_cycle");
    return escrever_long(caminho, pulso_ns);
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

static int fechar_porta_superior(void)
{
    if (camera_area_segura != RESPOSTA_SIM) {
        printf("[SEGURANCA] Fechamento bloqueado: area ainda nao confirmada como segura.\n");
        return 1;
    }

    printf("[ELETRONICA] Fechando porta superior.\n");

    if (mover_servo(PWM_PORTA_ESQUERDA, PORTA_ESQ_FECHADA_NS) != 0) {
        return -1;
    }
    if (mover_servo(PWM_PORTA_DIREITA, PORTA_DIR_FECHADA_NS) != 0) {
        return -1;
    }

    return 0;
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
    printf("[BinGo] Ciclo encerrado. Aguardando TOQUE_TELA_INICIAR.\n");
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

    time_t segundos = agora.tv_sec - instante_abertura_escotilha.tv_sec;
    return segundos >= TEMPO_QUEDA_SEGUNDOS;
}

/*
 * API de integracao.
 * A outra camada do sistema deve chamar estas funcoes quando os eventos ocorrerem.
 */
void bingo_evento_toque_iniciar(void)
{
    toque_tela_iniciar = true;
}

void bingo_evento_area_segura(bool segura)
{
    camera_area_segura = segura ? RESPOSTA_SIM : RESPOSTA_NAO;
}

void bingo_evento_classificacao_item(bool eletronico)
{
    camera_item_eletronico = eletronico ? RESPOSTA_SIM : RESPOSTA_NAO;
}

void bingo_evento_confirmacao_item(bool confirmado)
{
    toque_tela_confirmar_item = confirmado ? RESPOSTA_SIM : RESPOSTA_NAO;
}

/* Processa uma iteracao da maquina de estados sem bloquear a integracao externa. */
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
            printf("[SEGURANCA] Area insegura. Porta permanece aberta; aguardando nova verificacao.\n");
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
            printf("[INTEGRACAO] TELA_ITEM_NAO_ELETRONICO: solicitar retirada do item.\n");
            if (fechar_escotilha() != 0 || abrir_porta_superior() != 0) {
                return -1;
            }
            retornar_estado_inicial();
            return 0;
        }
        printf("[INTEGRACAO] TELA_CONFIRMAR_ITEM: aguardando confirmacao do usuario.\n");
        toque_tela_confirmar_item = RESPOSTA_PENDENTE;
        estado = ESTADO_AGUARDAR_CONFIRMACAO;
        return 0;

    case ESTADO_AGUARDAR_CONFIRMACAO:
        if (toque_tela_confirmar_item == RESPOSTA_PENDENTE) {
            return 0;
        }
        if (toque_tela_confirmar_item == RESPOSTA_NAO) {
            printf("[INTEGRACAO] Item nao confirmado; aguardando nova confirmacao.\n");
            toque_tela_confirmar_item = RESPOSTA_PENDENTE;
            return 0;
        }
        if (abrir_escotilha() != 0) {
            return -1;
        }
        clock_gettime(CLOCK_MONOTONIC, &instante_abertura_escotilha);
        estado = ESTADO_AGUARDAR_QUEDA;
        return 0;

    case ESTADO_AGUARDAR_QUEDA:
        if (!passaram_seis_segundos()) {
            return 0;
        }
        if (fechar_escotilha() != 0 || abrir_porta_superior() != 0) {
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
    const int canais[] = {
        PWM_PORTA_ESQUERDA,
        PWM_PORTA_DIREITA,
        PWM_ESCOTILHA_ESQUERDA,
        PWM_ESCOTILHA_DIREITA
    };

    if (geteuid() != 0) {
        fprintf(stderr, "Este controlador precisa de permissao para escrever em /sys/class/pwm. Execute como root/sudo.\n");
        return -1;
    }

    for (size_t i = 0; i < sizeof(canais) / sizeof(canais[0]); i++) {
        if (exportar_pwm(canais[i]) != 0) {
            return -1;
        }
    }

    /* Tempo curto para o sysfs criar pwm1..pwm4 apos exportacao. */
    struct timespec espera = {0, 200000000L};
    nanosleep(&espera, NULL);

    for (size_t i = 0; i < sizeof(canais) / sizeof(canais[0]); i++) {
        if (configurar_pwm(canais[i]) != 0) {
            return -1;
        }
    }

    return estado_inicial_fisico();
}

/*
 * Executavel de teste do modulo.
 * Na integracao final, a camada responsavel pode chamar bingo_inicializar(),
 * as funcoes bingo_evento_*() e bingo_processar() a partir do seu proprio loop.
 */
int main(void)
{
    printf("BinGo - Modulo eletronico Orange Pi\n");

    if (bingo_inicializar() != 0) {
        return EXIT_FAILURE;
    }

    while (true) {
        if (bingo_processar() != 0) {
            fprintf(stderr, "Falha no controlador eletronico.\n");
            return EXIT_FAILURE;
        }

        struct timespec ciclo = {0, 100000000L};
        nanosleep(&ciclo, NULL);
    }
}
