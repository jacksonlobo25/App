# JetBrains Gateway Devbox (Ubuntu + Java 21 + Node + PostgreSQL)

This repo provides ONLY the dev container. You will create your Spring Boot and React apps **inside** JetBrains Gateway.

## 1) Prepare your 4 public keys (Windows)
- Open `secrets/ssh/authorized_keys.list`
- Paste your **4 PUBLIC** keys (one per line). Comments/blank lines are OK.
- Do NOT put private keys anywhere in this repo.

## 2) Start the container
```bash
docker compose up -d --build
```
What it does:
- Starts PostgreSQL and creates DB/user from `.env`
- Installs your public keys into `~/.ssh/authorized_keys` inside the container (CRLF-safe)
- Starts SSH on port `${SSH_PORT}` (default 2222)

## 3) Connect via JetBrains Gateway (no manual docker exec)
- Gateway → New SSH Connection
    - Host: `localhost`
    - Port: value of `SSH_PORT` in `.env` (default 2222)
    - User: value of `DEV_USERNAME` in `.env` (default dev)
    - Auth: pick the matching private key from your machine
- Choose IntelliJ IDEA backend, project dir: `/workspace`

## 4) Create the Spring Boot backend **inside the remote session**
Option A: **Spring Initializr** (New Project Wizard)
    - New Project → Spring Initializr → Java 21, Gradle (Groovy), deps: Web, Spring Data JPA, PostgreSQL, Validation, Lombok
    - Place it under `/workspace/backend`
    - Add `application.yml` to read env variables (example):
    ```yaml
    server:
        port: 8080
    spring:
        datasource:
        url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:appdb}
        username: ${DB_USER:dev}
        password: ${DB_PASSWORD:devpass}
        jpa:
        hibernate:
            ddl-auto: update
        properties:
            hibernate:
            dialect: org.hibernate.dialect.PostgreSQLDialect
    ```
    - Run `bootRun` or use Spring Boot run configuration.

Option B: **Spring Boot CLI**
    ```bash
    cd /workspace
    spring init backend --build=gradle --java-version=21 --dependencies=web,data-jpa,postgresql,validation,lombok
    ```

## 5) Create the React frontend **inside the remote session**
```bash
cd /workspace
npm create vite@latest frontend -- --template react-ts
cd frontend
npm install
npm run dev
```
- Open `http://localhost:5173` on your host (port is already mapped by compose).
- Point API calls to `http://localhost:8080` (or use `VITE_API_URL`).

## 6) Database info (from .env)
- Host: `localhost`
- Port: `${POSTGRES_PORT}` (default 5432)
- DB: `${POSTGRES_DB}` (default appdb)
- User: `${POSTGRES_USER}` (default dev)
- Pass: `${POSTGRES_PASSWORD}` (default devpass)

## 7) Persistence
- Source code is bind-mounted to `/workspace`
- DB files in named volume `pgdata` (survives restarts/rebuilds)
- Remove everything with: `docker compose down -v` (danger: deletes DB data)

## 8) On-prem PostgreSQL (optional)
Inside container:
```bash
psql "host=pg-onprem.company.local port=5432 dbname=prod user=readonly sslmode=require" -c "select now();"
```
If you need a tunnel, create it on your host and point to `host.docker.internal:<local-port>`.

## 9) Troubleshooting
- If SSH refuses your keys on Windows: the script copies your list file and fixes Linux permissions before sshd starts.
- Check logs: `docker compose logs -f dev`
- Verify ports are mapped and free on your host.