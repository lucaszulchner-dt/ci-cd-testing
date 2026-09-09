FROM python:3.12-alpine

WORKDIR /app
COPY app.py .

ENV PORT=8080
ENV ENV_NAME=unassigned
ENV APP_VERSION=v0.0.0
ENV GIT_SHA=unknown

EXPOSE 8080

CMD ["python", "-u", "app.py"]
