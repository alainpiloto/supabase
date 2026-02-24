FROM supabase/postgres:15.8.1.085

# Supabase bootstrap SQL required by the official self-hosted stack.
COPY sql/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY sql/webhooks.sql /docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql
COPY sql/roles.sql /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
COPY sql/jwt.sql /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql
COPY sql/_supabase.sql /docker-entrypoint-initdb.d/migrations/97-_supabase.sql
COPY sql/logs.sql /docker-entrypoint-initdb.d/migrations/99-logs.sql
COPY sql/pooler.sql /docker-entrypoint-initdb.d/migrations/99-pooler.sql
