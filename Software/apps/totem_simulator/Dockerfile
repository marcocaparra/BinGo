FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    BINGO_RUNTIME_MODE=cloud

WORKDIR /app
COPY vision/requirements.txt vision/requirements.txt
RUN pip install --no-cache-dir -r vision/requirements.txt
COPY index.html style.css app.js backend_client.js runtime.js ./
COPY vision/vision_provider.js vision/edge_vision_service.py vision/

USER 10001:10001
CMD ["python", "vision/edge_vision_service.py"]
