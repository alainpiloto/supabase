# Runbook: Desplegar Supabase Backend en Railway

## 1) Objetivo

Este runbook documenta como desplegar un backend self-hosted de Supabase en Railway para un entorno productivo o staging.

Incluye:

- Arquitectura recomendada en Railway.
- Orden de despliegue.
- Variables por servicio.
- Validaciones de humo.
- Rollback.
- Troubleshooting de errores comunes.

No incluye:

- Deploy de tu app frontend/backend (solo backend Supabase).
- Hardening avanzado de seguridad (WAF, mTLS, SOC2, etc).

---

## 2) Arquitectura recomendada (MVP estable)

Servicios minimos:

1. `supabase-db` (Postgres Supabase image)
2. `supabase-auth` (GoTrue)
3. `supabase-rest` (PostgREST)
4. `supabase-storage` (Storage API)
5. `supabase-imgproxy` (image transform)
6. `supabase-realtime` (Realtime)
7. `supabase-kong` (API gateway publico)

Servicios opcionales:

1. `supabase-meta`
2. `supabase-studio`
3. `supabase-functions`
4. `supabase-analytics`
5. `supabase-pooler`

Recomendacion practica:

- Exponer publico solo `supabase-kong`.
- Mantener el resto en red privada de Railway.

---

## 3) Prerrequisitos

1. Cuenta Railway.
2. Proyecto Railway nuevo, por ejemplo `flowinggo-supabase-prod`.
3. Repo clonado con este stack (`/docker/docker-compose.yml`).
4. Dominio final para API (opcional pero recomendado), por ejemplo `supabase-api.tudominio.com`.

---

## 4) Preparar secretos y valores base

Desde este repo:

```bash
cd /Users/alainpiloto/projects/flowinggo-ecosystem/supabase/docker
cp .env.example .env
sh ./utils/generate-keys.sh
```

Guarda estos valores en un vault (1Password, Bitwarden, AWS Secrets Manager, etc):

- `POSTGRES_PASSWORD`
- `JWT_SECRET`
- `ANON_KEY`
- `SERVICE_ROLE_KEY`
- `SECRET_KEY_BASE`
- `VAULT_ENC_KEY`
- `PG_META_CRYPTO_KEY`
- `LOGFLARE_PUBLIC_ACCESS_TOKEN`
- `LOGFLARE_PRIVATE_ACCESS_TOKEN`
- `DASHBOARD_USERNAME`
- `DASHBOARD_PASSWORD`

Tambien define:

- `SITE_URL` = URL publica de tu app (ej: `https://app.flowinggo.com`)
- `API_EXTERNAL_URL` = URL publica de Kong en Railway (ej: `https://supabase-api.flowinggo.com`)

---

## 5) Preparar configuracion Railway (importante)

`docker-compose.yml` usa hostnames internos de Docker (`auth`, `rest`, `storage`, etc). En Railway debes usar dominios privados reales de cada servicio.

Por eso crea dos archivos para Railway:

1. `docker/volumes/api/kong.railway.yml`
2. Dockerfiles de deploy para `db` y `kong` (porque requieren archivos locales dentro del contenedor).

### 5.1 `kong.railway.yml`

Basado en `docker/volumes/api/kong.yml`, reemplaza upstreams:

- `http://auth:9999` -> `http://$AUTH_UPSTREAM`
- `http://rest:3000` -> `http://$REST_UPSTREAM`
- `http://storage:5000` -> `http://$STORAGE_UPSTREAM`
- `http://realtime-dev.supabase-realtime:4000` -> `http://$REALTIME_UPSTREAM`
- `http://studio:3000` -> `http://$STUDIO_UPSTREAM` (en Railway suele ser `:8080`)

Si no desplegaras Studio/Meta, elimina o comenta rutas `dashboard`, `meta`, `mcp`.

Importante:

- `DASHBOARD_USERNAME` y `DASHBOARD_PASSWORD` solo protegen Studio cuando Studio se expone detras de Kong con ruta `/*` + plugin `basic-auth`.
- Si publicas `supabase-studio` directamente en Railway, esas credenciales no aplican a ese dominio directo.

### 5.2 Dockerfile para Kong

Ejemplo:

```dockerfile
FROM kong:2.8.1
COPY docker/volumes/api/kong.railway.yml /home/kong/temp.yml
ENTRYPOINT ["bash","-c","eval \"echo \\\"$$(cat ~/temp.yml)\\\"\" > ~/kong.yml && /docker-entrypoint.sh kong docker-start"]
```

### 5.3 Dockerfile para DB

Necesario para copiar scripts de init (`docker/volumes/db/*.sql`) usados por Supabase.

Ejemplo:

```dockerfile
FROM supabase/postgres:15.8.1.085

COPY docker/volumes/db/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY docker/volumes/db/webhooks.sql /docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql
COPY docker/volumes/db/roles.sql /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
COPY docker/volumes/db/jwt.sql /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql
COPY docker/volumes/db/_supabase.sql /docker-entrypoint-initdb.d/migrations/97-_supabase.sql
COPY docker/volumes/db/logs.sql /docker-entrypoint-initdb.d/migrations/99-logs.sql
COPY docker/volumes/db/pooler.sql /docker-entrypoint-initdb.d/migrations/99-pooler.sql
```

---

## 6) Crear servicios en Railway (orden recomendado)

## Paso A: `supabase-db`

1. Crea servicio desde Dockerfile de DB.
2. Agrega volumen persistente en `/var/lib/postgresql/data`.
3. Variables minimas:
   - `POSTGRES_HOST=/var/run/postgresql`
   - `POSTGRES_PORT=5432`
   - `PGPORT=5432`
   - `POSTGRES_DB=postgres`
   - `PGDATABASE=postgres`
   - `POSTGRES_PASSWORD=<secret>`
   - `PGPASSWORD=<secret>`
   - `JWT_SECRET=<secret>`
   - `JWT_EXP=3600`
4. Start command:
   - `postgres -c config_file=/etc/postgresql/postgresql.conf -c log_min_messages=fatal`
5. Espera estado healthy.

Guarda su dominio privado como `DB_PRIVATE_HOST`.

## Paso B: `supabase-auth`

Imagen: `supabase/gotrue:v2.186.0`

Variables minimas:

- `GOTRUE_API_HOST=0.0.0.0`
- `GOTRUE_API_PORT=9999`
- `API_EXTERNAL_URL=https://<tu-kong-public-url>`
- `GOTRUE_DB_DRIVER=postgres`
- `GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:<POSTGRES_PASSWORD>@<DB_PRIVATE_HOST>:5432/postgres`
- `GOTRUE_SITE_URL=<SITE_URL>`
- `GOTRUE_URI_ALLOW_LIST=`
- `GOTRUE_DISABLE_SIGNUP=false`
- `GOTRUE_JWT_SECRET=<JWT_SECRET>`
- `GOTRUE_JWT_EXP=3600`
- `GOTRUE_JWT_AUD=authenticated`
- `GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated`
- `GOTRUE_JWT_ADMIN_ROLES=service_role`
- `GOTRUE_EXTERNAL_EMAIL_ENABLED=true`
- `GOTRUE_MAILER_AUTOCONFIRM=false`
- `GOTRUE_EXTERNAL_PHONE_ENABLED=true`
- `GOTRUE_SMS_AUTOCONFIRM=true`

Google OAuth (si aplica):

- `GOTRUE_EXTERNAL_GOOGLE_ENABLED=true`
- `GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID=<google-client-id>`
- `GOTRUE_EXTERNAL_GOOGLE_SECRET=<google-client-secret>`
- `GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI=https://<tu-kong-public-url>/auth/v1/callback`

Guarda dominio privado como `AUTH_PRIVATE_HOST`.

## Paso C: `supabase-rest`

Imagen: `postgrest/postgrest:v14.5`

Variables:

- `PGRST_DB_URI=postgres://authenticator:<POSTGRES_PASSWORD>@<DB_PRIVATE_HOST>:5432/postgres`
- `PGRST_DB_SCHEMAS=public,storage,graphql_public`
- `PGRST_DB_ANON_ROLE=anon`
- `PGRST_JWT_SECRET=<JWT_SECRET>`
- `PGRST_DB_USE_LEGACY_GUCS=false`
- `PGRST_APP_SETTINGS_JWT_SECRET=<JWT_SECRET>`
- `PGRST_APP_SETTINGS_JWT_EXP=3600`

Guarda dominio privado como `REST_PRIVATE_HOST`.

## Paso D: `supabase-imgproxy`

Imagen: `darthsim/imgproxy:v3.30.1`

Variables:

- `IMGPROXY_BIND=:5001`
- `IMGPROXY_LOCAL_FILESYSTEM_ROOT=/`
- `IMGPROXY_USE_ETAG=true`
- `IMGPROXY_ENABLE_WEBP_DETECTION=true`
- `IMGPROXY_MAX_SRC_RESOLUTION=16.8`

Si usas file storage local, agrega volumen para compartir assets con Storage (no recomendado para HA).

Guarda dominio privado como `IMGPROXY_PRIVATE_HOST`.

## Paso E: `supabase-storage`

Imagen: `supabase/storage-api:v1.37.8`

Variables minimas:

- `ANON_KEY=<ANON_KEY>`
- `SERVICE_KEY=<SERVICE_ROLE_KEY>`
- `POSTGREST_URL=http://<REST_PRIVATE_HOST>:3000`
- `PGRST_JWT_SECRET=<JWT_SECRET>`
- `DATABASE_URL=postgres://supabase_storage_admin:<POSTGRES_PASSWORD>@<DB_PRIVATE_HOST>:5432/postgres`
- `REQUEST_ALLOW_X_FORWARDED_PATH=true`
- `FILE_SIZE_LIMIT=52428800`
- `TENANT_ID=stub`
- `REGION=stub`
- `ENABLE_IMAGE_TRANSFORMATION=true`
- `IMGPROXY_URL=http://<IMGPROXY_PRIVATE_HOST>:5001`

Backend de archivos:

- Opcion A (simple): `STORAGE_BACKEND=file`, volumen en `/var/lib/storage`, `FILE_STORAGE_BACKEND_PATH=/var/lib/storage`
- Opcion B (recomendada prod): `STORAGE_BACKEND=s3` y configurar endpoint/keys S3.

Guarda dominio privado como `STORAGE_PRIVATE_HOST`.

## Paso F: `supabase-realtime`

Imagen: `supabase/realtime:v2.76.5`

Variables minimas:

- `PORT=4000`
- `DB_HOST=<DB_PRIVATE_HOST>`
- `DB_PORT=5432`
- `DB_USER=supabase_admin`
- `DB_PASSWORD=<POSTGRES_PASSWORD>`
- `DB_NAME=postgres`
- `DB_AFTER_CONNECT_QUERY=SET search_path TO _realtime`
- `DB_ENC_KEY=supabaserealtime`
- `API_JWT_SECRET=<JWT_SECRET>`
- `SECRET_KEY_BASE=<SECRET_KEY_BASE>`
- `ERL_AFLAGS=-proto_dist inet_tcp`
- `DNS_NODES=''`
- `RLIMIT_NOFILE=10000`
- `APP_NAME=realtime`
- `SEED_SELF_HOST=true`
- `RUN_JANITOR=true`
- `DISABLE_HEALTHCHECK_LOGGING=true`

Guarda dominio privado como `REALTIME_PRIVATE_HOST`.

## Paso G: `supabase-kong` (publico)

Servicio publico principal.

Dockerfile: usa el Dockerfile de Kong (seccion 5.2).

Variables:

- `KONG_DATABASE=off`
- `KONG_DECLARATIVE_CONFIG=/home/kong/kong.yml`
- `KONG_DNS_ORDER=LAST,A,CNAME`
- `KONG_PLUGINS=request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction`
- `KONG_NGINX_PROXY_PROXY_BUFFER_SIZE=160k`
- `KONG_NGINX_PROXY_PROXY_BUFFERS=64 160k`
- `SUPABASE_ANON_KEY=<ANON_KEY>`
- `SUPABASE_SERVICE_KEY=<SERVICE_ROLE_KEY>`
- `DASHBOARD_USERNAME=<DASHBOARD_USERNAME>`
- `DASHBOARD_PASSWORD=<DASHBOARD_PASSWORD>`
- `AUTH_UPSTREAM=<AUTH_PRIVATE_HOST>:9999`
- `REST_UPSTREAM=<REST_PRIVATE_HOST>:3000`
- `STORAGE_UPSTREAM=<STORAGE_PRIVATE_HOST>:5000`
- `REALTIME_UPSTREAM=<REALTIME_PRIVATE_HOST>:4000`
- `STUDIO_UPSTREAM=<STUDIO_PRIVATE_HOST>:8080`

Expone puerto `8000` y asigna dominio publico final.

Para modo seguro recomendado:

- No expongas dominio publico de `supabase-studio`.
- Accede a Studio via dominio publico de `supabase-kong` (ruta `/*`) con Basic Auth.

---

## 7) Migraciones de aplicacion (FlowingGo)

Una vez arriba el stack, aplica migraciones de tu app.

Ejemplo (desde `flowingGo`):

```bash
docker exec -i supabase-db psql -U postgres -d postgres < supabase/migrations/00003_auth_profiles_cutover.sql
docker exec -i supabase-db psql -U postgres -d postgres < supabase/migrations/00004_reminders_header_gallery.sql
docker exec -i supabase-db psql -U postgres -d postgres < supabase/migrations/00005_google_calendar_status_sync.sql
```

Si ejecutas contra Railway remoto, usa `psql` con la URL privada/publica del DB de Railway.

---

## 8) Smoke tests obligatorios

Usa el dominio publico de Kong (`SUPABASE_URL`):

```bash
export SUPABASE_URL="https://<tu-kong-public-url>"
export ANON_KEY="<anon_key>"
export SERVICE_ROLE_KEY="<service_role_key>"

curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: ${ANON_KEY}" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  "${SUPABASE_URL}/auth/v1/health"

curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: ${ANON_KEY}" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  "${SUPABASE_URL}/rest/v1/"

curl -s -o /dev/null -w "%{http_code}\n" \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  "${SUPABASE_URL}/storage/v1/status"
```

Esperado: `200` (o `401` controlado en endpoints que requieren auth), nunca `404` ni `502`.

Test de schema cache PostgREST:

```bash
curl -s \
  -H "apikey: ${SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
  "${SUPABASE_URL}/rest/v1/google_oauth_tokens?select=user_id&limit=1"
```

Si falla con `PGRST205`, aplica migracion faltante y recarga schema:

```sql
NOTIFY pgrst, 'reload schema';
```

---

## 9) Cutover de aplicaciones

En tu app (web/mobile/backend), actualizar:

- `NEXT_PUBLIC_SUPABASE_URL` = dominio de Kong
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` = `ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` = `SERVICE_ROLE_KEY`

Luego redeploy de la app.

---

## 10) Rollback

Plan rapido:

1. Mantener URL/keys anteriores guardadas.
2. Si hay incidente, regresar app a URL/keys anteriores.
3. Detener trafico a nuevo Kong.
4. Corregir causa (variables, rutas Kong, DB, migraciones).
5. Repetir smoke tests antes de reintentar cutover.

---

## 11) Troubleshooting rapido

## Error `PGRST205 ... table ... not found in schema cache`

Causa:

- Migracion no aplicada o cache de PostgREST vieja.

Fix:

1. Aplicar SQL faltante.
2. `NOTIFY pgrst, 'reload schema';`
3. Si persiste, reiniciar servicio `supabase-rest`.

## Error OAuth callback Google

Verificar:

- `GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI` apunta al dominio de Kong `/auth/v1/callback`.
- En Google Console estan configurados los redirect URIs exactos.

## Storage devuelve 500 o no guarda archivos

Verificar:

- `DATABASE_URL` de storage.
- backend (`file` con volumen o `s3` con credenciales correctas).
- conectividad con `imgproxy`.

## Realtime no conecta

Verificar:

- `_realtime` schema existe.
- `DB_AFTER_CONNECT_QUERY` correcto.
- ruta Kong `/realtime/v1/` configurada a realtime service.

---

## 12) Recomendaciones operativas

1. Usa staging y production separados en Railway.
2. Haz backup/snapshot antes de cada cambio mayor.
3. Versiona tus migraciones SQL en git.
4. No expongas `SERVICE_ROLE_KEY` a cliente.
5. Documenta y rota secretos periodicamente.
