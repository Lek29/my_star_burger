# 1. Используем официальный slim-образ Python (Debian-based)
FROM python:3.11-slim

# Настройки для оптимизации Python в Docker
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# 2. Устанавливаем CURL + NODE.JS + PARCEL
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    curl \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g parcel@2 \
    && rm -rf /var/lib/apt/lists/*

# 3. Копируем и устанавливаем Python-зависимости
COPY backend/requirements.txt .
RUN python -m pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# 4. Копируем весь код проекта
COPY backend/ .

# 5. Копируем фронтенд для сборки (нужно для parcel)
COPY frontend/bundles-src/ ./bundles-src/
COPY frontend/package.json ./

# 6. Устанавливаем Node.js зависимости для сборки
RUN npm install

EXPOSE 8000

# Команда запуска Gunicorn
CMD ["gunicorn", "star_burger.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]
