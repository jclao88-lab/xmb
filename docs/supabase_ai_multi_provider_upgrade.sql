-- Upgrade an existing ai_model_catalog installation for multiple AI providers.
-- Safe to run after supabase_ai_model_catalog.sql; existing reports are preserved.

begin;

alter table public.ai_model_catalog
add column if not exists endpoint_secret_name text;

alter table public.ai_model_catalog
drop constraint if exists ai_model_catalog_provider_check;

alter table public.ai_model_catalog
add constraint ai_model_catalog_provider_check
check (provider in ('openai', 'anthropic', 'google', 'custom_1', 'custom_2', 'custom_3'));

insert into public.ai_model_catalog (
  model_key,
  display_name,
  provider,
  provider_model_id,
  secret_name,
  endpoint_secret_name,
  supports_structured_output,
  allowed_roles,
  is_active,
  sort_order
)
values
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

commit;
