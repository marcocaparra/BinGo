import os
import cv2
import base64
import requests
import time
import json
import threading
from typing import Optional, Tuple, Dict, Any
from ultralytics import YOLO

BACKEND_URL = os.getenv("BINGO_BACKEND_URL", "http://localhost:8000")
CLASSIFY_ENDPOINT = f"{BACKEND_URL}/device/classify_image"

YOLO_WEIGHTS = os.getenv("BINGO_YOLO_WEIGHTS", "yolov8n.pt")
DETECT_CONF = float(os.getenv("BINGO_DETECT_CONF", "0.25"))
NMS_IOU = float(os.getenv("BINGO_NMS_IOU", "0.45"))
MIN_BOX_AREA = int(os.getenv("BINGO_MIN_BOX_AREA", "1200"))
HEADLESS = os.getenv("BINGO_HEADLESS", "0") == "1"

model = YOLO(YOLO_WEIGHTS)

CLASSES_ELECTRONIC = {
    63,  # laptop
    64,  # mouse
    65,  # remote
    66,  # keyboard
    67,  # cell phone
    72,  # tv
}

CLASSES_COMMON = {
    39,  # bottle
    41,  # cup
}

CLASSES_IGNORE = {
    43,  # knife
    44,  # spoon
    45,  # fork
    46,  # bowl
    47,  # banana
    48,  # apple
    49,  # sandwich
    50,  # orange
    51,  # broccoli
    52,  # carrot
    53,  # hot dog
    54,  # pizza
    55,  # donut
    56,  # cake

    57,  # chair
    58,  # couch
    59,  # potted plant
    60,  # bed
    61,  # dining table
    62,  # toilet
    69,  # oven
    71,  # sink
    72,  # tv
    73,  # laptop stand / book / etc.
    74,  # mousepad / livro /
    75,  # refrigerator
    76,  # book
    77,  # clock
    78,  # vase
    79,  # scissors
    80,  # teddy bear
    81,  # hair drier
    82,  # toothbrush

    2,   # bicycle
    3,   # car
    4,   # motorcycle
    6,   # bus
    7,   # train
    8,   # truck
    9,   # boat
    1,   # person
}


COOLDOWN_SECONDS = 3
last_classification_time: Dict[int, float] = {}

def encode_image_to_base64(image_np) -> str:
    ok, buffer = cv2.imencode(".jpeg", image_np, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    if not ok:
        raise RuntimeError("Falha ao codificar a imagem para JPEG.")
    return base64.b64encode(buffer).decode("utf-8")


def send_to_backend(base64_image: str, class_name: str):
    """Executa em thread → não trava a câmera"""
    try:
        payload = {"image_base64": base64_image}
        resp = requests.post(CLASSIFY_ENDPOINT, json=payload, timeout=10)

        if resp.status_code == 200:
            resp_json = resp.json()
            print(f"[BACKEND] {class_name} → {resp_json}")
        else:
            print(f"[BACKEND] HTTP {resp.status_code}: {resp.text[:200]}")

    except Exception as e:
        print(f"[BACKEND] Erro ao enviar {class_name}: {e}")


def _draw_label(img, text: str, x: int, y: int, color: Tuple[int, int, int]):
    y_txt = max(15, y - 10)
    cv2.putText(img, text, (x, y_txt), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2, cv2.LINE_AA)

def detect_objects_and_classify():
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Erro: Não foi possível abrir a webcam.")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    print("==== BinGo Vision ====")
    print(f"Backend: {BACKEND_URL}")
    print(f"Endpoint: {CLASSIFY_ENDPOINT}")
    print("Pressione 'q' para sair.\n")

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break

            results = model(frame, stream=True, conf=DETECT_CONF, iou=NMS_IOU, verbose=False)

            for r in results:
                if not r.boxes:
                    continue

                for box in r.boxes:
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    confidence = float(box.conf[0])
                    class_id = int(box.cls[0])
                    class_name = model.names.get(class_id, str(class_id))

                    area = (x2 - x1) * (y2 - y1)
                    if area < MIN_BOX_AREA:
                        continue

                    if class_id in CLASSES_IGNORE:
                        continue

                    now = time.time()
                    if now - last_classification_time.get(class_id, 0) < COOLDOWN_SECONDS:
                        continue

                    if class_id in CLASSES_COMMON:
                        label = "Não Eletrônico"
                        color = (255, 0, 0)
                        last_classification_time[class_id] = now
                        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
                        _draw_label(frame, f"{label} ({class_name})", x1, y1, color)
                        continue

                    if class_id in CLASSES_ELECTRONIC:
                        # crop + resize antes de enviar
                        cropped = frame[max(0,y1):y2, max(0,x1):x2]
                        if cropped.size == 0:
                            continue
                        cropped_resized = cv2.resize(cropped, (256, 256))

                        b64_img = encode_image_to_base64(cropped_resized)
                        threading.Thread(target=send_to_backend, args=(b64_img, class_name), daemon=True).start()

                        last_classification_time[class_id] = now
                        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
                        _draw_label(frame, f"{class_name}: {confidence:.2f}", x1, y1, (0, 255, 0))

            if not HEADLESS:
                cv2.imshow("BinGo Vision", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break

    finally:
        cap.release()
        if not HEADLESS:
            cv2.destroyAllWindows()
        print("BinGo Vision encerrado.")

if __name__ == "__main__":
    detect_objects_and_classify()