# Supabase For Dummies (Este Proyecto)

Guía práctica, paso a paso, para trabajar con Supabase en este repositorio sin perder tiempo.

## 1) Qué hay en este proyecto

Este repo usa Supabase self-hosted con Docker Compose (`/docker/docker-compose.yml`).

Servicios principales:

- `supabase-studio`: dashboard de Supabase
- `supabase-kong`: API Gateway (entrada principal)
- `supabase-db`: PostgreSQL
- `supabase-meta`: API interna para administrar PostgreSQL (schemas, tablas, queries)
- `supabase-auth`, `supabase-rest`, `realtime`, `storage`, `supabase-pooler`, etc.

Puertos importantes (por defecto):

- `http://localhost:8000`: entrada principal (Kong, API y acceso a Studio)
- `https://localhost:8443`: Kong HTTPS
- `localhost:5432`: conexión DB (a través de Supavisor/pooler)
- `localhost:6543`: pool transaccional (Supavisor)

## 2) Setup inicial (primera vez)

Desde la raíz del repo:

```bash
cd docker
cp .env.example .env
sh ./utils/generate-keys.sh
docker compose up -d
docker compose ps
```

Notas:

- Cuando corras `generate-keys.sh`, acepta actualizar `.env` (`y`) para generar secretos reales.
- No uses los valores por defecto de `.env.example` en producción.

## 3) Llaves y secretos: cuáles son y para qué sirven

Archivo principal: `docker/.env`

Variables más importantes:

- `JWT_SECRET`: secreto base para firmar JWT.
- `ANON_KEY`: key pública para clientes (frontend).
- `SERVICE_ROLE_KEY`: key privilegiada, solo backend/servidor.
- `POSTGRES_PASSWORD`: password principal de PostgreSQL (muchos servicios dependen de esto).
- `PG_META_CRYPTO_KEY`: clave para cifrar/descifrar `x-connection-encrypted` entre Studio y `postgres-meta`.
- `SECRET_KEY_BASE`: usado por servicios internos (ej. pooler/analytics).
- `VAULT_ENC_KEY`: cifrado interno de secretos.
- `LOGFLARE_PUBLIC_ACCESS_TOKEN` y `LOGFLARE_PRIVATE_ACCESS_TOKEN`: analytics/logs.
- `DASHBOARD_USERNAME` y `DASHBOARD_PASSWORD`: acceso a Studio.

## 4) Cómo generar las keys correctamente

Forma recomendada (automática):

```bash
cd docker
sh ./utils/generate-keys.sh
```

Este script genera y/o actualiza:

- `JWT_SECRET`
- `ANON_KEY`
- `SERVICE_ROLE_KEY`
- `SECRET_KEY_BASE`
- `VAULT_ENC_KEY`
- `PG_META_CRYPTO_KEY`
- tokens de Logflare
- credenciales S3/minio
- `POSTGRES_PASSWORD`
- `DASHBOARD_PASSWORD`

Importante:

- Si cambias `JWT_SECRET`, debes regenerar también `ANON_KEY` y `SERVICE_ROLE_KEY`.
- Si cambias `POSTGRES_PASSWORD` en una instancia ya corriendo, no lo edites “a mano” sin rotarlo en DB.

## 5) Cómo levantar Supabase correctamente

Inicio normal:

```bash
cd docker
docker compose up -d
```

Ver estado:

```bash
cd docker
docker compose ps
```

Recrear servicios al cambiar variables de entorno:

```bash
cd docker
docker compose up -d --force-recreate
```

Ver logs:

```bash
cd docker
docker logs -f supabase-meta
docker logs -f supabase-studio
docker logs -f supabase-db
```

## 6) Checklist rápido de salud

Con API key (desde raíz):

```bash
ANON_KEY=$(grep '^ANON_KEY=' docker/.env | cut -d= -f2-)
SERVICE_ROLE_KEY=$(grep '^SERVICE_ROLE_KEY=' docker/.env | cut -d= -f2-)

curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: ${ANON_KEY}" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  http://localhost:8000/auth/v1/health

curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: ${ANON_KEY}" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  http://localhost:8000/rest/v1/

curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  http://localhost:8000/storage/v1/health
```

Si todo está bien, deberías ver `200` en los 3.

## 7) Qué hacer después de cambios

### A) Cambios de código frontend/backend (sin tocar Docker/env)

No hace falta recrear todo. Reinicia solo tu proceso local de desarrollo.

### B) Cambios en `docker/.env`

Aplica recreación de servicios:

```bash
cd docker
docker compose up -d --force-recreate
```

### C) Cambiaste `POSTGRES_PASSWORD` en una instancia existente

Usa el script oficial del repo para rotar password dentro de DB + `.env`:

```bash
cd docker
sh ./utils/db-passwd.sh
docker compose up -d --force-recreate
```

### D) Cambios en SQL/migraciones del proyecto

Opción rápida para aplicar una migración manual en la instancia local:

```bash
docker exec -i supabase-db psql -U postgres -d postgres < supabase/migrations/TU_MIGRACION.sql
```

Si quieres reset completo de data local (destructivo):

```bash
cd docker
docker compose down -v --remove-orphans
rm -rf volumes/db/data volumes/storage
docker compose up -d
```

`docker/reset.sh` también sirve, pero además puede resetear `.env`.

### E) Cambios en `docker/docker-compose.yml`

```bash
cd docker
docker compose pull
docker compose up -d
```

## 8) Error común: `failed to process upstream connection details`

Qué significa:

- `supabase-meta` no pudo interpretar la conexión cifrada que le envía Studio/cliente.

Señales en logs:

- `failed to parse encrypted connstring`
- `Malformed UTF-8 data`
- `failed to get connection string`

Causas típicas:

- `PG_META_CRYPTO_KEY` distinto entre caller y `supabase-meta`.
- Header `x-connection-encrypted` enviado vacío, `undefined`, `null` o corrupto.
- Tienes dos instancias/procesos mezclados (por ejemplo un Next local y Studio en Docker).

Cómo arreglar:

1. Verifica `PG_META_CRYPTO_KEY` en `docker/.env`.
2. Si corres Studio local desde código fuente, pon el mismo valor en `apps/studio/.env`.
3. Reinicia procesos locales de Node/Next y recrea Docker:

```bash
cd docker
docker compose up -d --force-recreate
```

4. Vuelve a revisar:

```bash
docker logs -f supabase-meta
```

No deberían aparecer más errores de `connstring`.

## 9) Muy importante: no mezclar modos sin control

En este repo puedes terminar con dos “Studios”:

- Studio en Docker (vía `http://localhost:8000`)
- App/Studio local en otro proceso Node (por ejemplo `localhost:3000`)

Si ambos están activos y con `.env` distintos, tendrás errores difíciles de depurar.

Regla simple:

- Para operar Supabase self-hosted, usa solo `http://localhost:8000`.
- Si vas a correr Studio local, alinea sus variables sensibles con `docker/.env`.

## 10) Buenas prácticas de Postgres/Supabase (resumen)

- Usa `UUID` como PK para entidades nuevas.
- Activa RLS y define políticas explícitas por tabla.
- Evita `SELECT *` en queries de app; pide columnas concretas.
- Crea índices para filtros y joins reales (`WHERE`, `JOIN`, `ORDER BY`).
- Prefiere `upsert(..., { onConflict: ... })` en lugar de read-then-write.
- Usa constraints (`NOT NULL`, `CHECK`, `UNIQUE`, `FK`) para proteger la integridad.

## 11) Seguridad mínima antes de producción

- Regenera todos los secretos de `docker/.env`.
- Nunca compartas ni comitees `.env` (`docker/.gitignore` ya lo protege).
- Limita uso de `SERVICE_ROLE_KEY` a backend seguro.
- Configura backups de DB antes de cualquier actualización mayor.

## 12) Comandos que usarás todo el tiempo

```bash
# Levantar stack
cd docker && docker compose up -d

# Ver estado
cd docker && docker compose ps

# Ver logs de meta (clave para errores de schemas/query)
cd docker && docker logs -f supabase-meta

# Reaplicar contenedores tras cambios de env
cd docker && docker compose up -d --force-recreate

# Ejecutar SQL manual
docker exec -i supabase-db psql -U postgres -d postgres < supabase/migrations/TU_MIGRACION.sql
```

---

Si sigues estos pasos, deberías poder operar tu entorno local de Supabase de forma estable y sin sorpresas.
