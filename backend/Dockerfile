FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Установка curl, Node.js, Parcel
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g parcel@2 \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY backend/requirements.txt .
RUN pip install --upgrade pip && pip install --no-cache-dir -r requirements.txt

# Код
COPY backend/ .
COPY frontend/bundles-src/ ./bundles-src/
COPY frontend/package.json ./
COPY frontend/package-lock.json ./

# Установка node deps
RUN npm install

CMD ["gunicorn", "star_burger.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]
