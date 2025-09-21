#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <esp_camera.h>
#include <ArduinoJson.h> // Para JSON
#include <base64.h> // Inclui o cabeçalho Base64 do framework Arduino para ESP32

// ==========================================================
// 1. Configurações de Rede Wi-Fi
// ==========================================================
const char* ssid = "JesusCristo_2.4G";        // <<--- SUBSTITUA PELA SUA REDE WI-FI
const char* password = "JesusCristo#7!"; // <<--- SUBSTITUA PELA SENHA DA SUA REDE

// ==========================================================
// 2. Configurações do Backend (Ajuste o IP do seu PC)
// ==========================================================
// IMPORTANTE: Este NÃO PODE ser 'localhost'. Encontre o IP da sua máquina na rede local
//             Ex: 192.168.1.100 ou o IP que o Docker está usando para expor o serviço
const char* backend_host = "192.168.0.32"; // <<--- SUBSTITUA PELO IP DO SEU PC (ONDE O DOCKER ESTÁ RODANDO)
const int backend_port = 8000;
const char* classify_image_endpoint = "/device/classify_image";

// ==========================================================
// 3. Pinagem da Câmera OV2640 (para AI-Thinker ESP32-CAM)
// ==========================================================
// Estas definições são padrão para a maioria das placas AI-Thinker ESP32-CAM
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1 // -1 significa que o pino de reset é gerenciado automaticamente
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27

#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

#define LED_GPIO_NUM       4 // LED Flash / LED "onboard" da ESP32-CAM

// ==========================================================
// Funções Auxiliares
// ==========================================================

// Função para inicializar a câmera
bool initCamera() {
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
    config.pin_sscb_sda = SIOD_GPIO_NUM;
    config.pin_sscb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn = PWDN_GPIO_NUM;
    config.pin_reset = RESET_GPIO_NUM;
    config.xclk_freq_hz = 20000000;       // Frequência do clock da câmera
    config.pixel_format = PIXFORMAT_JPEG; // Formato de pixel JPEG para compressão eficiente
    config.frame_size = FRAMESIZE_QQVGA;    // Resolução da imagem (VGA = 640x480)
    config.jpeg_quality = 50;             // Qualidade JPEG (0-63, 0=melhor qualidade, 63=pior qualidade/menor arquivo)
    config.fb_count = 1;                  // Número de frame buffers

    // Inicializa a câmera
    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        Serial.printf("Falha na inicialização da câmera! Erro: 0x%x\n", err);
        return false;
    }

    // Configurações adicionais da câmera (opcional, mas útil)
    sensor_t * s = esp_camera_sensor_get();
    if (s) {
        s->set_vflip(s, 1);       // Inverte a imagem verticalmente (útil se a câmera estiver invertida)
        s->set_hmirror(s, 1);     // Espelha a imagem horizontalmente
        s->set_framesize(s, FRAMESIZE_QQVGA); // Pode redefinir aqui se precisar de outra resolução
        s->set_quality(s, 50);    // Qualidade JPEG, menor para mais compressão
        // s->set_brightness(s, 1); // Ajusta o brilho (+2 a -2)
        // s->set_contrast(s, 1);   // Ajusta o contraste (+2 a -2)
    }
    digitalWrite(LED_GPIO_NUM, HIGH); // Liga o LED flash para auxiliar na captura
    Serial.println("Câmera inicializada com sucesso!");
    return true;
}

// ==========================================================
// Configuração Inicial (Executa uma vez na inicialização)
// ==========================================================
void setup() {
    Serial.begin(115200); // Inicia a comunicação Serial para depuração
    delay(100);

    // Configura o LED flash
    pinMode(LED_GPIO_NUM, OUTPUT);
    digitalWrite(LED_GPIO_NUM, LOW); // LED desligado por padrão

    Serial.println("Inicializando o ESP32-CAM...");

    // Conecta ao Wi-Fi
    WiFi.begin(ssid, password);
    Serial.print("Conectando ao WiFi.");
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi Conectado!");
    Serial.print("Endereço IP: ");
    Serial.println(WiFi.localIP());

    // Inicializa a câmera
    if (!initCamera()) {
        Serial.println("Reiniciando ESP32 devido a falha na câmera...");
        delay(5000);
        ESP.restart(); // Reinicia se a câmera não iniciar
    }

    Serial.println("Setup concluído. Pronto para capturar e enviar imagens.");
}

// ==========================================================
// Loop Principal (Executa repetidamente)
// ==========================================================
void loop() {
    Serial.println("Aguardando 10 segundos antes da próxima captura...");
    delay(10000); // Aguarda 10 segundos antes de capturar a próxima imagem para testes

    Serial.println("Capturando imagem...");
    camera_fb_t * fb = esp_camera_fb_get(); // Tenta obter um frame da câmera
    if (!fb) {
        Serial.println("Falha na captura do frame da câmera!");
        return; // Retorna para tentar novamente no próximo loop
    }

    Serial.printf("Frame capturado! Tamanho: %d bytes\n", fb->len);

    // ==========================================================
    // Converte a imagem JPEG para Base64
    // ==========================================================
    // A biblioteca 'base64.h' que vamos criar converte os bytes da imagem
    String base64Image = base64::encode(reinterpret_cast<const uint8_t*>(fb->buf), fb->len);

    // É CRÍTICO liberar o frame buffer da câmera após o uso!
    esp_camera_fb_return(fb);

    Serial.printf("Imagem convertida para Base64. Tamanho da string: %d bytes\n", base64Image.length());

    // ==========================================================
    // Envia a imagem Base64 para o Backend via HTTP POST
    // ==========================================================
    if (WiFi.status() == WL_CONNECTED) {
        HTTPClient http;
        String serverPath = String("http://") + backend_host + ":" + backend_port + classify_image_endpoint;

        http.begin(serverPath);
        http.addHeader("Content-Type", "application/json");

        // Construir o JSON usando ArduinoJson
        StaticJsonDocument<3000> doc; // Capacidade do JSON (ajuste conforme necessário, 25000+ bytes para Base64)
        doc["image_base64"] = base64Image;

        String requestBody;
        serializeJson(doc, requestBody);

        Serial.print("Enviando requisição HTTP POST para ");
        Serial.println(serverPath);
        Serial.printf("Tamanho do payload JSON: %d bytes\n", requestBody.length());

        int httpResponseCode = http.POST(requestBody);

        if (httpResponseCode > 0) {
            Serial.printf("[HTTP] Código de Resposta: %d\n", httpResponseCode);
            String payload = http.getString();
            Serial.println("Resposta do Backend:");
            Serial.println(payload);

            // ==========================================================
            // Processa a resposta JSON do Backend
            // ==========================================================
            StaticJsonDocument<512> responseDoc; // Capacidade para a resposta do backend
            DeserializationError error = deserializeJson(responseDoc, payload);

            if (error) {
                Serial.print(F("Falha na leitura do JSON de resposta: "));
                Serial.println(error.f_str());
            } else {
                bool is_e_waste = responseDoc["is_e_waste"];
                String material_type_name = responseDoc["material_type_name"].as<String>();
                String action = responseDoc["action"].as<String>();
                String unique_code = responseDoc["unique_code"].as<String>();
                String message = responseDoc["message"].as<String>();

                Serial.printf("Classificação: %s (E-waste: %s)\n", material_type_name.c_str(), is_e_waste ? "Sim" : "Não");
                Serial.printf("Ação solicitada: %s\n", action.c_str());
                Serial.printf("Mensagem: %s\n", message.c_str());
                if (unique_code.length() > 0) {
                    Serial.printf("Código Único Gerado: %s\n", unique_code.c_str());
                }

                // ==========================================================
                // Executa ações com base na resposta do Backend
                // ==========================================================
                if (action == "OPEN_ELECTRONIC_BIN") {
                    Serial.println("Acionando compartimento de eletrônicos! (Simulação)");
                    // AQUI VOCÊ IMPLEMENTARIA O CÓDIGO PARA ABRIR O COMPARTIMENTO DE LIXO ELETRÔNICO
                    // Exemplo: digitalWrite(PIN_SERVO_E_WASTE, HIGH); delay(1000); digitalWrite(PIN_SERVO_E_WASTE, LOW);
                } else if (action == "OPEN_RECOVER_BIN") {
                    Serial.println("Acionando compartimento de reciclagem geral! (Simulação)");
                    // AQUI VOCÊ IMPLEMENTARIA O CÓDIGO PARA ABRIR O COMPARTIMENTO DE RECICLÁVEIS GERAIS
                    // Exemplo: digitalWrite(PIN_SERVO_RECOVER, HIGH); delay(1000); digitalWrite(PIN_SERVO_RECOVER, LOW);
                } else {
                    Serial.println("Ação desconhecida ou não especificada.");
                }
            }
        } else {
            Serial.printf("[HTTP] Erro na requisição. Código: %d - %s\n", httpResponseCode, http.errorToString(httpResponseCode).c_str());
        }
        http.end(); // Fecha a conexão HTTP
    } else {
        Serial.println("WiFi desconectado. Tentando reconectar...");
        WiFi.begin(ssid, password);
    }
}