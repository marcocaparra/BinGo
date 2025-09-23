import os
import google.generativeai as genai
from google.generativeai.types import HarmCategory, HarmBlockThreshold
import base64
import json
from typing import Tuple # Importe Tuple para a anotação de tipo da função

# --- Configuração da API do Gemini ---
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise ValueError("GEMINI_API_KEY não encontrada nas variáveis de ambiente.")

genai.configure(api_key=GEMINI_API_KEY)

# --- Inicialização do Modelo Gemini (usando o modelo identificado) ---
# Usamos 'gemini-1.5-pro-latest' porque seu log mostrou que ele está disponível
# e é um modelo multimodal poderoso.
model = genai.GenerativeModel('gemini-1.5-pro-latest')

# --- Funções de Classificação de Imagem ---
async def classify_image_with_gemini(image_base64: str) -> Tuple[str, float, str]:
    try:
        image_bytes = base64.b64decode(image_base64)
        
        # O prompt precisa estar com aspas duplas internas escapadas!
        prompt_parts = [
            """Analise a imagem deste resíduo e forneça uma classificação e descrição.

Instruções:
1. Classifique o item como 'Eletrônico' ou 'Não Eletrônico'.
2. Forneça uma breve descrição do item que você identificou.

Responda estritamente no seguinte formato JSON:
{"classification": "Eletrônico" ou "Não Eletrônico", "description": "descrição do item"}""",
            {
                "mime_type": "image/jpeg",
                "data": image_bytes
            }
        ]

        # Envie a requisição para o Gemini
        response = await model.generate_content_async(
            prompt_parts,
            safety_settings={
                HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_NONE,
                HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_NONE,
                HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_NONE,
                HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_NONE,
            },
            generation_config=genai.GenerationConfig(temperature=0.2, max_output_tokens=100)
        )

        raw_text = ""
        if response and response.candidates:
            for candidate in response.candidates:
                if candidate.content and candidate.content.parts:
                    for part in candidate.content.parts:
                        if hasattr(part, 'text'):
                            raw_text += part.text

        if not raw_text:
            raise ValueError("A API Gemini não retornou uma resposta textual válida.")

        ia_response_json = json.loads(raw_text.strip())

        classification = ia_response_json.get("classification", "")
        description = ia_response_json.get("description", "Desconhecido")

        if "eletrônico" in classification.lower():
            return "Eletrônico", 0.95, description
        else:
            return "Não Eletrônico", 0.80, description

    except Exception as e:
        print(f"Erro ao classificar imagem com Gemini: {e}")
        return "Não Eletrônico", 0.5, f"Erro na IA: {str(e)}"