# JetBrains Gateway Devbox (Supabase; ALL env in .env)

- No local PostgreSQL server. Use **Supabase** via variables in `.env`.
- Java 21, Node (via NodeSource), Python 3.13 (pyenv), Maven/Gradle/Spring Boot CLI (SDKMAN).
- SSH server for JetBrains Gateway.
- Your 4 public keys auto-installed from `secrets/ssh/authorized_keys.list`.

## 1) Put your 4 public keys
Edit `secrets/ssh/authorized_keys.list` and paste your four **PUBLIC** keys (one per line).

## 2) Fill `.env` (already populated with your Supabase values)
- `DATABASE_URL` = postgresql://postgres:dockergalaxe@db.rejzasofjxflpgzdefkv.supabase.co:5432/postgres
- `DATABASE_URL_JDBC` = jdbc:postgresql://db.rejzasofjxflpgzdefkv.supabase.co:5432/postgres
- `DB_USER`, `DB_PASSWORD` etc.
- Keep `.env` out of Git (already in .gitignore).

## 3) Start container
```bash
docker compose up -d --build
```

## 4) Connect with JetBrains Gateway
- Host: localhost
- Port: ${SSH_PORT} (2222 by default)
- User: ${DEV_USERNAME} (dev by default)
- Auth: choose the matching private key

## 5) Create your apps inside /workspace
- Spring Boot (Initializr or CLI). Point datasource at env:
  ```yaml
  spring:
    datasource:
      url: ${SPRING_DATASOURCE_URL:${DATABASE_URL_JDBC}}
      username: ${SPRING_DATASOURCE_USERNAME:${DB_USER}}
      password: ${SPRING_DATASOURCE_PASSWORD:${DB_PASSWORD}}
  server:
    port: 8080
  ```
- React (Vite): `npm create vite@latest frontend -- --template react-ts` then `npm run dev`.
  Call backend at `http://localhost:8080` (or set `VITE_API_URL`).

## 6) Test DB from container
```bash
psql "$DATABASE_URL" -c "select now();"
```

## 7) Stop / start
```bash
docker compose stop
docker compose start
docker compose up -d --build  # after changing versions in .env
```
