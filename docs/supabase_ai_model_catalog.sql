-- Incremental schema for selectable AI models and report-design sessions.
-- Run after supabase_smart_query_schema.sql and supabase_rls_permissions.sql.

begin;

create table if not exists public.ai_model_catalog (
  model_key text primary key,
  display_name text not null,
  provider text not null check (provider in ('openai', 'anthropic', 'google', 'custom_1', 'custom_2', 'custom_3')),
  provider_model_id text not null,
  secret_name text not null default 'OPENAI_API_KEY',
  endpoint_secret_name text,
  supports_structured_output boolean not null default true,
  allowed_roles text[] not null default array['owner', 'manager']::text[],
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ai_model_catalog
add column if not exists endpoint_secret_name text;

alter table public.ai_model_catalog
drop constraint if exists ai_model_catalog_provider_check;

alter table public.ai_model_catalog
add constraint ai_model_catalog_provider_check
check (provider in ('openai', 'anthropic', 'google', 'custom_1', 'custom_2', 'custom_3'));

alter table public.saved_reports
add column if not exists model_key text references public.ai_model_catalog(model_key) on delete set null;

create table if not exists public.report_design_sessions (
  id uuid primary key default gen_random_uuid(),
  model_key text references public.ai_model_catalog(model_key) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'designed', 'executed', 'saved', 'cancelled')),
  draft jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.report_design_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.report_design_sessions(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_model_catalog_active on public.ai_model_catalog(is_active, sort_order);
create index if not exists idx_report_design_sessions_user on public.report_design_sessions(created_by, updated_at desc);
create index if not exists idx_report_design_messages_session on public.report_design_messages(session_id, created_at);

drop trigger if exists set_ai_model_catalog_updated_at on public.ai_model_catalog;
create trigger set_ai_model_catalog_updated_at before update on public.ai_model_catalog
for each row execute function public.set_updated_at();

drop trigger if exists set_report_design_sessions_updated_at on public.report_design_sessions;
create trigger set_report_design_sessions_updated_at before update on public.report_design_sessions
for each row execute function public.set_updated_at();

insert into public.ai_model_catalog (model_key, display_name, provider, provider_model_id, secret_name, endpoint_secret_name, supports_structured_output, allowed_roles, is_active, sort_order)
values
  ('openai-report-designer', 'OpenAI Report Designer', 'openai', 'gpt-5.6-sol', 'OPENAI_API_KEY', null, true, array['owner','manager'], true, 10),
  ('claude-report-designer', 'Claude Report Designer', 'anthropic', 'claude-sonnet-5', 'ANTHROPIC_API_KEY', null, true, array['owner','manager'], false, 20),
  ('gemini-report-designer', 'Gemini Report Designer', 'google', 'gemini-3.5-flash', 'GEMINI_API_KEY', null, true, array['owner','manager'], false, 30),
  ('provider-1-report-designer', 'Provider 1', 'custom_1', 'replace-with-provider-model-id', 'PROVIDER_1_API_KEY', 'PROVIDER_1_BASE_URL', true, array['owner','manager'], false, 40),
  ('provider-2-report-designer', 'Provider 2', 'custom_2', 'replace-with-provider-model-id', 'PROVIDER_2_API_KEY', 'PROVIDER_2_BASE_URL', true, array['owner','manager'], false, 50),
  ('provider-3-report-designer', 'Provider 3', 'custom_3', 'replace-with-provider-model-id', 'PROVIDER_3_API_KEY', 'PROVIDER_3_BASE_URL', true, array['owner','manager'], false, 60)
on conflict (model_key) do update set
  display_name = excluded.display_name,
  provider = excluded.provider,
  secret_name = excluded.secret_name,
  endpoint_secret_name = excluded.endpoint_secret_name,
  supports_structured_output = excluded.supports_structured_output,
  allowed_roles = excluded.allowed_roles,
  sort_order = excluded.sort_order;

alter table public.ai_model_catalog enable row level security;
alter table public.report_design_sessions enable row level security;
alter table public.report_design_messages enable row level security;

drop policy if exists "owner manager read active ai models" on public.ai_model_catalog;
drop policy if exists "owner manages ai models" on public.ai_model_catalog;
drop policy if exists "users read own report design sessions or owner reads all" on public.report_design_sessions;
drop policy if exists "owner manager create own report design sessions" on public.report_design_sessions;
drop policy if exists "users update own report design sessions or owner updates all" on public.report_design_sessions;
drop policy if exists "users read messages for own report sessions or owner reads all" on public.report_design_messages;
drop policy if exists "owner manager create messages for own report sessions" on public.report_design_messages;

create policy "owner manager read active ai models" on public.ai_model_catalog for select to authenticated
using (public.is_active_user() and is_active and public.has_role(allowed_roles));
create policy "owner manages ai models" on public.ai_model_catalog for all to authenticated
using (public.has_role(array['owner'])) with check (public.has_role(array['owner']));

create policy "users read own report design sessions or owner reads all" on public.report_design_sessions for select to authenticated
using (public.is_active_user() and (created_by = auth.uid() or public.has_role(array['owner'])));
create policy "owner manager create own report design sessions" on public.report_design_sessions for insert to authenticated
with check (public.has_role(array['owner', 'manager']) and created_by = auth.uid());
create policy "users update own report design sessions or owner updates all" on public.report_design_sessions for update to authenticated
using (created_by = auth.uid() or public.has_role(array['owner']))
with check (created_by = auth.uid() or public.has_role(array['owner']));

create policy "users read messages for own report sessions or owner reads all" on public.report_design_messages for select to authenticated
using (exists (select 1 from public.report_design_sessions s where s.id = session_id and (s.created_by = auth.uid() or public.has_role(array['owner']))));
create policy "owner manager create messages for own report sessions" on public.report_design_messages for insert to authenticated
with check (exists (select 1 from public.report_design_sessions s where s.id = session_id and s.created_by = auth.uid() and public.has_role(array['owner', 'manager'])));

commit;
