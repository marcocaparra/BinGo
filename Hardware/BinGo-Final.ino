#include <Wire.h>
#include <LiquidCrystal_I2C.h>

LiquidCrystal_I2C lcd(0x27, 16, 2); // Endereço comum para I2C 16x2

const int sensorIR1 = 2;       // Sensor IR 1
const int sensorIR2 = 3;       // Sensor IR 2
const int buzzerPin = 7;       // Buzzer

bool podeGerar = true;         // Evita múltiplos códigos em sequência

void setup() {
  pinMode(sensorIR1, INPUT);git push -u origin main
  pinMode(sensorIR2, INPUT);
  pinMode(buzzerPin, OUTPUT);

  lcd.init();
  lcd.backlight();

  // Mensagem inicial
  lcd.setCursor(0, 0);
  lcd.print("BinGo");
  lcd.setCursor(0, 1);
  lcd.print("iniciando...");
  tone(buzzerPin, 1000, 250);
  delay(2000);
  lcd.clear();
}

void loop() {
  int estadoIR1 = digitalRead(sensorIR1);
  int estadoIR2 = digitalRead(sensorIR2);

  // Agora considera o descarte quando QUALQUER sensor for DESATIVADO (HIGH)
  if ((estadoIR1 == HIGH || estadoIR2 == HIGH) && podeGerar) {
    delay(50); // Debounce simples
    if (digitalRead(sensorIR1) == HIGH || digitalRead(sensorIR2) == HIGH) {
      podeGerar = false;

      // Feedback sonoro
      tone(buzzerPin, 1000);
      delay(200);
      noTone(buzzerPin);

      // Exibe código de recompensa
      String codigo = gerarCodigo();
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("Aproveite seus");
      lcd.setCursor(0, 1);
      lcd.print("Bins: " + codigo);
      delay(4000);

      // Mensagem motivacional
      lcd.clear();
      mostrarMensagemMotivacional();
      tone(buzzerPin, 1500, 200);
      delay(4000);

      // Reinício da interface
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("Pronto para");
      lcd.setCursor(0, 1);
      lcd.print("outro!");
      delay(2000);
    }
  } else if (estadoIR1 == LOW && estadoIR2 == LOW) {
    podeGerar = true; // Reset da flag
    lcd.setCursor(0, 0);
    lcd.print("Descarte o lixo");
    lcd.setCursor(0, 1);
    lcd.print("eletronico aqui!");
  }
}

// Gera código aleatório de 6 letras (A-Z)
String gerarCodigo() {
  String codigo = "";
  for (int i = 0; i < 6; i++) {
    char letra = char(random(65, 91)); // ASCII A-Z
    codigo += letra;
  }
  return codigo;
}

// Mensagens motivacionais aleatórias
void mostrarMensagemMotivacional() {
  int indice = random(0, 15);
  lcd.clear();

  switch (indice) {
    case 0: lcd.print("Boa. O planeta"); lcd.setCursor(0, 1); lcd.print("sorri pra voce!"); break;
    case 1: lcd.print("A natureza diz:"); lcd.setCursor(0, 1); lcd.print("Obrigado! :)"); break;
    case 2: lcd.print("Voce fez a sua"); lcd.setCursor(0, 1); lcd.print("parte. Parabens!"); break;
    case 3: lcd.print("Menos lixo e"); lcd.setCursor(0, 1); lcd.print("mais futuro!"); break;
    case 4: lcd.print("De atitude!"); lcd.setCursor(0, 1); lcd.print("Planeta feliz!"); break;
    case 5: lcd.print("A Terra te diz:"); lcd.setCursor(0, 1); lcd.print("Valeu mesmo!"); break;
    case 6: lcd.print("Exemplo dado!"); lcd.setCursor(0, 1); lcd.print("Continue assim"); break;
    case 7: lcd.print("Pequeno gesto,"); lcd.setCursor(0, 1); lcd.print("grande impacto!"); break;
    case 8: lcd.print("Isso sim e ser"); lcd.setCursor(0, 1); lcd.print("consciente!"); break;
    case 9: lcd.print("Descarte certo!"); lcd.setCursor(0, 1); lcd.print("Planeta limpo!"); break;
    case 10: lcd.print("Show de atitude!"); lcd.setCursor(0, 1); lcd.print("Valeu demais!"); break;
    case 11: lcd.print("O meio ambiente"); lcd.setCursor(0, 1); lcd.print("agradece! :)"); break;
    case 12: lcd.print("Voce fez a"); lcd.setCursor(0, 1); lcd.print("diferenca!"); break;
    case 13: lcd.print("BinGo te aplaude"); lcd.setCursor(0, 1); lcd.print("com buzina!"); break;
    case 14: lcd.print("Pequenas acoes"); lcd.setCursor(0, 1); lcd.print("mudam o mundo!"); break;
  }
}
