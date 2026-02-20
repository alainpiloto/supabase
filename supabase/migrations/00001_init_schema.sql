-- ==========================================
-- FLOWINGGO - INIT SCHEMA (SUPABASE)
-- ==========================================

-- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) users (espejo lógico de NextAuth)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(255),
  image TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

-- 2) reminders_config (1:1 por user)
CREATE TABLE reminders_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  prompt TEXT NOT NULL DEFAULT '',
  anticipation_time_amount INTEGER NOT NULL DEFAULT 15 CHECK (anticipation_time_amount >= 0),
  anticipation_time_unit VARCHAR(50) NOT NULL DEFAULT 'minutes',
  timezone VARCHAR(100) NOT NULL DEFAULT 'UTC',
  header_type VARCHAR(20) NOT NULL DEFAULT 'text',
  header_content TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT reminders_config_header_type_check CHECK (header_type IN ('text', 'image')),
  CONSTRAINT reminders_config_user_id_unique UNIQUE (user_id)
);

-- 3) contacts (normalización de datos de contacto)
CREATE TABLE contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ws_number VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT contacts_user_ws_unique UNIQUE (user_id, ws_number)
);

CREATE INDEX idx_contacts_user_ws ON contacts(user_id, ws_number);

-- 4) conversations (evento principal de recordatorio)
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  wa_id VARCHAR(50) NOT NULL,
  calendar_id VARCHAR(255) NOT NULL DEFAULT 'primary',
  ws_event_id VARCHAR(255) NOT NULL,
  init_message_id VARCHAR(255),
  event_date TIMESTAMPTZ NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT conversations_user_event_unique UNIQUE (user_id, ws_event_id)
);

CREATE INDEX idx_conv_wa_id ON conversations(wa_id);
CREATE INDEX idx_conv_date ON conversations(event_date);
CREATE INDEX idx_conv_user_calendar_date ON conversations(user_id, calendar_id, event_date);
CREATE INDEX idx_conv_contact ON conversations(contact_id);

-- 5) conversation_events (append-only)
CREATE TABLE conversation_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  event_type VARCHAR(50) NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX idx_conv_events_conv_id ON conversation_events(conversation_id);
CREATE INDEX idx_conv_events_conv_created_at ON conversation_events(conversation_id, created_at);
CREATE INDEX idx_conv_events_type ON conversation_events(event_type);

-- ==========================================
-- SEGURIDAD (RLS)
-- ==========================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminders_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_events ENABLE ROW LEVEL SECURITY;
