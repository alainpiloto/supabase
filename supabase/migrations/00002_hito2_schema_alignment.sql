-- ==========================================
-- FLOWINGGO - HITO 2 ALIGNMENT (INCREMENTAL)
-- ==========================================
-- Este script alinea instalaciones existentes con el esquema objetivo de 00001_init_schema.sql.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Conversations: columnas requeridas por el servicio Supabase
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS user_id UUID,
  ADD COLUMN IF NOT EXISTS wa_id VARCHAR(50),
  ADD COLUMN IF NOT EXISTS calendar_id VARCHAR(255) NOT NULL DEFAULT 'primary',
  ADD COLUMN IF NOT EXISTS init_message_id VARCHAR(255);

-- Backfill para instalaciones previas (derivando desde contacts)
UPDATE public.conversations c
SET
  user_id = ct.user_id,
  wa_id = ct.ws_number
FROM public.contacts ct
WHERE c.contact_id = ct.id
  AND (c.user_id IS NULL OR c.wa_id IS NULL);

ALTER TABLE public.conversations
  ALTER COLUMN user_id SET NOT NULL,
  ALTER COLUMN wa_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'conversations_user_id_fkey'
      AND conrelid = 'public.conversations'::regclass
  ) THEN
    ALTER TABLE public.conversations
      ADD CONSTRAINT conversations_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'conversations_user_event_unique'
      AND conrelid = 'public.conversations'::regclass
  ) THEN
    ALTER TABLE public.conversations
      ADD CONSTRAINT conversations_user_event_unique UNIQUE (user_id, ws_event_id);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_conv_wa_id ON public.conversations(wa_id);
CREATE INDEX IF NOT EXISTS idx_conv_user_calendar_date
  ON public.conversations(user_id, calendar_id, event_date);
CREATE INDEX IF NOT EXISTS idx_conv_events_conv_created_at
  ON public.conversation_events(conversation_id, created_at);

-- conversation_events payload append-only estricto
UPDATE public.conversation_events
SET payload = '{}'::jsonb
WHERE payload IS NULL;

ALTER TABLE public.conversation_events
  ALTER COLUMN payload SET DEFAULT '{}'::jsonb,
  ALTER COLUMN payload SET NOT NULL;

-- reminders_config: limitar header_type al contrato final
UPDATE public.reminders_config
SET header_type = 'text'
WHERE header_type IS NULL
   OR header_type NOT IN ('text', 'image');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'valid_header_type'
      AND conrelid = 'public.reminders_config'::regclass
  ) THEN
    ALTER TABLE public.reminders_config
      DROP CONSTRAINT valid_header_type;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'reminders_config_header_type_check'
      AND conrelid = 'public.reminders_config'::regclass
  ) THEN
    ALTER TABLE public.reminders_config
      ADD CONSTRAINT reminders_config_header_type_check
      CHECK (header_type IN ('text', 'image'));
  END IF;
END
$$;
