FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY backend/requirements.txt .

RUN python -m pip install --upgrade pip \
  && pip install --no-cache-dir -r requirements.txt


COPY backend/ .

EXPOSE 8000

CMD ["gunicorn", "star_burger.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]
