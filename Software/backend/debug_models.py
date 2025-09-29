import os
import google.generativeai as genai

genai.configure(api_key=os.getenv("GEMINI_API_KEY"))

print("=== Modelos disponíveis ===")
for m in genai.list_models():
    print(m.name)
