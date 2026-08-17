FROM python:3.12-slim-bookworm
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py store.py auth.py access.py db.py ./
ENV DATA_DIR=/data
ENV STATIC_DIR=/var/www
ENV PORT=3000
# /data — named volume agronizer_data in compose (VAPID, subscriptions). Access DB via DATABASE_URL.
VOLUME ["/data", "/var/www"]
EXPOSE 3000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-3000}"]
