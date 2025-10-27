# 1. Используем официальный slim-образ Python (Debian-based)
FROM python:3.11-slim

# Настройки для оптимизации Python в Docker
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ: Устанавливаем CURL для Healthcheck (используя apt-get)
# Без этой утилиты команда healthcheck внутри контейнера завершится ошибкой "command not found".
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Копируем и устанавливаем зависимости
COPY backend/requirements.txt .

RUN python -m pip install --upgrade pip \
  && pip install --no-cache-dir -r requirements.txt

# Копируем весь остальной код проекта
# Используем COPY backend/ . как в вашем оригинале
COPY backend/ .

EXPOSE 8000

# Команда запуска Gunicorn (из вашего оригинала)
CMD ["gunicorn", "star_burger.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]
