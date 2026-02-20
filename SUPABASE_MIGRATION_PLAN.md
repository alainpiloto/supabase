# Plan de Implementación y Mantenimiento: Migración a Supabase

Este documento describe la estrategia paso a paso para migrar la dependencia backend de Strapi a **Supabase** dentro del proyecto Next.js App Router (FlowingGo), garantizando alta escalabilidad, seguridad y apego a las **mejores prácticas de PostgreSQL de Supabase**.

## 🎯 Resumen de Objetivos
1. Desacoplar Strapi y reemplazarlo con el cliente `@supabase/supabase-js`.
2. Modelar un esquema SQL optimizado (UUIDs, snake_case, índices compuestos) en Supabase.
3. Crear adaptadores transaccionales de lectura y escritura (`lib/services/supabase/*`).
4. Implementar soporte de concurrencia de entornos (`USE_SUPABASE="true"`).
5. Implementar RLS (Row Level Security) e integridad referencial estricta, según las [Supabase Postgres Best Practices].

---

## 🏗 Fases de Implementación (Hitos)

### Hito 1: Setup, Dependencias y Arquitectura del Cliente
- **Instalación:** Instalar dependencias `@supabase/supabase-js`.
- **Variables de Entorno:** Integrar `NEXT_PUBLIC_SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` en el `.env.local` actual y los entornos productivos.
- **Cliente Singleton:** Implementar `lib/api/supabase-admin.ts` exportando la instancia del cliente con `service_role` (ya que Next.js asume el rol de backend de confianza).
- **Pooling & Conexiones (Best Practice `conn-1`):** Asegurar que las llamadas al cliente sean eficientes y evitar fugas de conexiones al iniciar el singleton globalmente en entornos de desarrollo.

### Hito 2: Generación y Optimización del Esquema SQL
Se generará el archivo `supabase/migrations/00001_init_schema.sql` con un enfoque estricto de rendimiento y seguridad (`schema-`, `security-` best practices):

1. **Tabla `users`**: 
   - Espejo de los usuarios de NextAuth.
   - Uso de `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`.

2. **Tabla `reminders_config`**: 
   - Tabla 1-a-1 ligada al `user_id`.
   - Limpiar propiedades JSON dispersas. 
   - **Constraints (Best Practice `schema-`):** `CHECK (header_type IN ('text', 'image'))`.

3. **Tabla `contacts`**: 
   - Normalización de emails y teléfonos (`ws_number`).
   - **Índices Parciales/Compuestos (Best Practice `query-`):** `CREATE INDEX idx_contacts_user_ws ON contacts(user_id, ws_number)`.

4. **Tabla `conversations`**: 
   - Seguimiento de eventos principales.
   - **Índices de Rendimiento:** `CREATE INDEX idx_conv_date ON conversations(event_date)`.

5. **Tabla `conversation_events`**: 
   - Tabla dependiente (`conversations.id`) usando `ON DELETE CASCADE`.
   - **Data Access Pattern (`data-`):** Diseño Append-Only (evitar mutar JSONB pesados de forma concurrente, insertar de forma inmutable).

6. **Seguridad (RLS - Best Practice `security-1`):**
   - Habilitar `ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;` en todas las tablas por defecto (aunque Next.js use Service Role, asegura control estricto a nivel base de datos).

### Hito 3: Adaptadores de Servicios Base (Lecturas)
Las operaciones "Read" se migrarán a una arquitectura tipada en `lib/services/supabase/`:
- `users.ts` → `getSupabaseUserIdByEmail()`
- `contacts.ts` → `getUserContacts()`, `getUserContactsPage()`, `findUserContactByWsNumber()`
- `conversations.ts` → `getConversationsByDate()`, `getConversationsByRange()`
- `reminders-config.ts` → `getUserWithRemindersConfig()`

**Consideración de Rendimiento:** Se empleará `select()` explícito limitando la descarga de columnas e integrando paginación asíncrona optimizada (`range()`, `limit()`).

### Hito 4: Adaptadores Transaccionales (Escrituras)
Se extenderán los archivos del Hito 3 con persistencias de datos:
- **Upserts Nativos (Best Practice `lock-1`):** En lugar de hacer read-then-write corriendo el riesgo del problema de concurrencia, utilizar `supabase.from('...').upsert(..., { onConflict: 'user_id, ws_number' })`.
- **Logs Incrementales:** Insertar directamente a `conversation_events` de forma masiva sobre arreglos vía `.insert([...])` sin transacciones escalonadas costosas.

### Hito 5: Inyección y Dualidad en los Endpoints (Feature Flag)
Adaptación de Next.js (`app/api/*`) para operar en un estado dual de transición suave:
- Inyección condicional validando `process.env.USE_SUPABASE === 'true'`.
- De estar habilitado, se llaman los servicios ubicados en `lib/services/supabase/*`.
- En caso contrario (default fallback), mantener `lib/services/strapi/*`.

### Hito 6: Soporte y Mantenimiento a Futuro
- **Diagnósticos (Best Practice `monitor-1`):** Establecer rutinas asíncronas para auditar el impacto del rendimiento temporal usando las métricas nativas de Supabase y el comando `pg_stat_statements_reset` tras implementar.
- Nunca romper ni purgar la carpeta `lib/services/strapi/*` hasta que todos los tests estén probados exitosamente bajo el stack de Supabase.

---
Se recomienda iniciar el **Hito 1** instalando dependencias y configurando variables de entorno en paralelo a iniciar la base de datos local vía `docker compose`.
