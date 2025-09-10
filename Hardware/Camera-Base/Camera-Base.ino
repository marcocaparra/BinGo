#define CAMERA_MODEL_AI_THINKER
#include "esp_camera.h"
#include <WiFi.h>

// ===========================
// Inclua a configuração de pinos para a AI-Thinker ESP32-CAM
// (Este arquivo 'camera_pins.h' vem com os exemplos do ESP32-CAM)
// ===========================
#include "camera_pins.h"

// ===========================
// Insira suas credenciais de WiFi
// ===========================
const char *ssid = "JesusCristo_2.4G";
const char *password = "JesusCristo#7!";

// Declaração da função startCameraServer.
// Ela geralmente está em outro arquivo/aba no exemplo CameraWebServer.
// Certifique-se de que ela esteja presente no seu projeto.
void startCameraServer();

// Se você usa o LED do flash, esta função também precisa ser definida.
// void setupLedFlash(); // Comentei, pois não está no seu código principal
// Se você for usar o LED do flash (PINO 4 na AI-Thinker), descomente e defina esta função.
// void setupLedFlash() {
//   pinMode(LED_GPIO_NUM, OUTPUT);
//   digitalWrite(LED_GPIO_NUM, LOW); // Liga o LED do flash (ou HIGH dependendo da placa)
// }


void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true); // Habilita saída de debug para o Serial
  Serial.println(); // Pula uma linha para melhor legibilidade

  Serial.println("Iniciando configuracao da camera...");

  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000; // Frequência do clock XCLK (20MHz é comum)
  
  // --- AJUSTES PARA QUALIDADE DA IMAGEM E REDUCAO DE RUIDO ---
  // A qualidade da imagem e o tamanho do arquivo JPEG estão inversamente relacionados.
  // Valores mais baixos (ex: 8-10) = MAIOR QUALIDADE, MAIOR ARQUIVO, MENOS RUÍDO DE COMPRESSÃO.
  // Valores mais altos (ex: 50-63) = MENOR QUALIDADE, MENOR ARQUIVO, MAIS RUÍDO DE COMPRESSÃO.
  config.jpeg_quality = 10; // Seu valor original era 12. 10 já dá uma pequena melhorada.
                             // Experimente 8 para qualidade máxima (e arquivos maiores).

  // Sua configuração original de frame_size (UXGA e depois QVGA)
  config.frame_size = FRAMESIZE_UXGA; // Resolução inicial (1600x1200)

  config.pixel_format = PIXFORMAT_JPEG; // Formato de pixel JPEG para compressão
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY; // Pega o frame mais antigo e livre
  config.fb_location = CAMERA_FB_IN_PSRAM; // Onde armazenar o frame buffer
  config.fb_count = 1; // Quantidade de frame buffers

  // Se houver PSRAM, use configurações mais altas
  if (config.pixel_format == PIXFORMAT_JPEG) {
    if (psramFound()) {
      Serial.println("PSRAM encontrada. Configurando para maior qualidade e 2 buffers.");
      config.jpeg_quality = 8; // Qualidade ainda melhor com PSRAM
      config.fb_count = 2; // Dois buffers para streaming mais suave
      config.grab_mode = CAMERA_GRAB_LATEST; // Pega o frame mais recente (melhor para streaming)
    } else {
      Serial.println("PSRAM nao encontrada. Ajustando configuracao para DRAM e SVGA.");
      config.frame_size = FRAMESIZE_SVGA; // Reduz a resolução se não houver PSRAM
      config.fb_location = CAMERA_FB_IN_DRAM; // Usa a DRAM se não houver PSRAM
    }
  }

  // Inicialização da câmera
  Serial.println("Inicializando a camera...");
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("ERRO: Inicializacao da camera falhou (0x%x). Verifique alimentacao e conexao.\n", err);
    return; // Para a execucao do setup se a camera nao inicializar
  }
  Serial.println("Camera inicializada com sucesso!");

  // =========================================================================
  // >>> BLOCO DE TESTE DE CAPTURA DE FRAME (O "CHUTE INICIAL") <<<
  // Este bloco é o que parece ter "desbloqueado" a câmera, forçando uma captura.
  // Ele também serve para diagnóstico.
  camera_fb_t *fb = NULL; // Ponteiro para o frame buffer
  Serial.println("Tentando capturar um frame de teste...");
  fb = esp_camera_fb_get(); // Tenta obter um frame buffer da câmera

  if (!fb) { // Se fb for NULL, a captura falhou
    Serial.println("ERRO: Captura de frame falhou (fb e NULL). A camera nao esta produzindo frames.");
  } else { // Se fb nao for NULL, um frame foi capturado
    Serial.printf("SUCESSO: Frame de teste capturado. Formato: %d, Tamanho: %d bytes.\n", fb->format, fb->len);
    // IMPORTANTE: Liberar o frame buffer apos o uso para que ele possa ser reutilizado
    esp_camera_fb_return(fb);
    Serial.println("Frame de teste retornado ao buffer.");
  }
  // >>> FIM DO BLOCO DE TESTE <<<
  // =========================================================================

  sensor_t *s = esp_camera_sensor_get();
  // Configurações adicionais para a OV2640, se necessário

  // Sua configuração original reduzia para QVGA. Mantida por compatibilidade com seu código.
  // Reduz o tamanho do frame para maior taxa de quadros e estabilidade inicial.
  s->set_framesize(s, FRAMESIZE_QVGA); 
  Serial.printf("Framesize ajustado para QVGA (320x240) para streaming mais rapido.\n");

  // --- AJUSTES FINAIS NO SENSOR (OV2640) PARA MELHOR QUALIDADE ---
  // Estes são CRUCIAIS para reduzir ruído e melhorar a imagem em diferentes condições de luz.
  // Automatic White Balance (AWB): Essencial para cores corretas. Mantenha ligado (1).
  s->set_whitebal(s, 1);     // Habilita AWB
  s->set_awb_gain(s, 1);     // Habilita ajuste de ganho do AWB

  // Automatic Gain Control (AGC) e Automatic Exposure Control (AEC):
  // Estes são CRUCIAIS para reduzir ruído em baixa luz.
  // Mantenha-os habilitados (1) para o melhor comportamento automático na maioria dos cenários.
  s->set_gain_ctrl(s, 1);    // Habilita AGC (controle de ganho automático)
  s->set_exposure_ctrl(s, 1);// Habilita AEC (controle de exposição automático)
  
  // Vira a imagem verticalmente, se necessário (ajuste conforme a montagem da câmera)
  s->set_vflip(s, 1); 
  // Espelha a imagem horizontalmente, se necessário
  s->set_hmirror(s, 1); 

#if defined(LED_GPIO_NUM)
  // Verifique se setupLedFlash() está definido se você usa esta linha.
  // setupLedFlash(); 
#endif

  // Conexão WiFi
  Serial.print("Conectando ao WiFi ");
  Serial.print(ssid);
  Serial.print("...");
  WiFi.begin(ssid, password);
  WiFi.setSleep(false); // Evita que o WiFi entre em modo sleep, o que pode causar instabilidade no streaming

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi conectado!");
  Serial.print("Endereco IP do ESP32-CAM: ");
  Serial.println(WiFi.localIP());

  startCameraServer(); // Inicia o servidor web da câmera

  Serial.print("Câmera pronta! Use 'http://");
  Serial.print(WiFi.localIP());
  Serial.println("' para conectar");
}

void loop() {
  // Apenas mantém o loop principal rodando, o servidor web faz todo o trabalho.
  delay(10000);
}