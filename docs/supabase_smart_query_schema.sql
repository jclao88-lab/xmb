-- Smart Query semantic layer and reusable report schema.
-- Run after supabase_schema.sql and supabase_rls_permissions.sql.
-- This script does not alter business data tables.

begin;

create extension if not exists pgcrypto;

create table if not exists public.semantic_metrics (
  id uuid primary key default gen_random_uuid(),
  metric_key text not null unique,
  zh_name text not null,
  en_name text not null,
  domain text not null check (domain in ('sales', 'purchase', 'inventory', 'cross_domain')),
  source_tables text[] not null,
  expression_hint text not null,
  result_type text not null check (result_type in ('number', 'currency', 'quantity', 'percentage')),
  allowed_roles text[] not null default array['owner', 'manager']::text[],
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.semantic_dimensions (
  id uuid primary key default gen_random_uuid(),
  dimension_key text not null unique,
  zh_name text not null,
  en_name text not null,
  domain text not null check (domain in ('sales', 'purchase', 'inventory', 'cross_domain')),
  source_tables text[] not null,
  expression_hint text not null,
  value_type text not null check (value_type in ('text', 'date', 'timestamp', 'number', 'status')),
  allowed_roles text[] not null default array['owner', 'manager']::text[],
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.semantic_relationships (
  id uuid primary key default gen_random_uuid(),
  relationship_key text not null unique,
  zh_name text not null,
  en_name text not null,
  left_table text not null,
  right_table text not null,
  join_type text not null default 'inner' check (join_type in ('inner', 'left')),
  join_condition_hint text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.semantic_examples (
  id uuid primary key default gen_random_uuid(),
  example_key text not null unique,
  zh_question text not null,
  en_question text,
  query_plan jsonb not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.query_intents (
  id uuid primary key default gen_random_uuid(),
  intent_key text not null unique,
  title text not null,
  zh_title text,
  description text,
  zh_description text,
  example_phrases jsonb not null default '[]'::jsonb,
  query_plan_template jsonb not null,
  parameter_schema jsonb not null default '[]'::jsonb,
  allowed_roles text[] not null default array['owner', 'manager']::text[],
  status text not null default 'pending' check (status in ('pending', 'active', 'rejected', 'disabled')),
  created_by uuid references public.users(id) on delete set null,
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.query_intent_proposals (
  id uuid primary key default gen_random_uuid(),
  source_question text not null,
  suggested_intent jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  submitted_by uuid not null references public.users(id) on delete restrict,
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.query_runs (
  id uuid primary key default gen_random_uuid(),
  source_question text not null,
  matched_intent_id uuid references public.query_intents(id) on delete set null,
  query_plan jsonb not null,
  result_summary jsonb,
  status text not null check (status in ('matched', 'temporary', 'failed', 'blocked')),
  error_message text,
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.saved_reports (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  zh_title text,
  description text,
  zh_description text,
  icon text not null default 'R' check (char_length(icon) between 1 and 40),
  report_definition jsonb not null,
  source_intent_id uuid references public.query_intents(id) on delete set null,
  allowed_roles text[] not null default array['owner', 'manager']::text[],
  is_active boolean not null default true,
  created_by uuid not null references public.users(id) on delete restrict,
  updated_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.report_versions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.saved_reports(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  report_definition jsonb not null,
  change_note text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (report_id, version_no)
);

create index if not exists idx_semantic_metrics_domain on public.semantic_metrics(domain, is_active);
create index if not exists idx_semantic_dimensions_domain on public.semantic_dimensions(domain, is_active);
create index if not exists idx_query_intents_status on public.query_intents(status);
create index if not exists idx_query_intent_proposals_status on public.query_intent_proposals(status, created_at desc);
create index if not exists idx_query_runs_created_by on public.query_runs(created_by, created_at desc);
create index if not exists idx_saved_reports_active on public.saved_reports(is_active, updated_at desc);
create index if not exists idx_report_versions_report on public.report_versions(report_id, version_no desc);

drop trigger if exists set_semantic_metrics_updated_at on public.semantic_metrics;
create trigger set_semantic_metrics_updated_at before update on public.semantic_metrics
for each row execute function public.set_updated_at();

drop trigger if exists set_semantic_dimensions_updated_at on public.semantic_dimensions;
create trigger set_semantic_dimensions_updated_at before update on public.semantic_dimensions
for each row execute function public.set_updated_at();

drop trigger if exists set_semantic_relationships_updated_at on public.semantic_relationships;
create trigger set_semantic_relationships_updated_at before update on public.semantic_relationships
for each row execute function public.set_updated_at();

drop trigger if exists set_semantic_examples_updated_at on public.semantic_examples;
create trigger set_semantic_examples_updated_at before update on public.semantic_examples
for each row execute function public.set_updated_at();

drop trigger if exists set_query_intents_updated_at on public.query_intents;
create trigger set_query_intents_updated_at before update on public.query_intents
for each row execute function public.set_updated_at();

drop trigger if exists set_query_intent_proposals_updated_at on public.query_intent_proposals;
create trigger set_query_intent_proposals_updated_at before update on public.query_intent_proposals
for each row execute function public.set_updated_at();

drop trigger if exists set_saved_reports_updated_at on public.saved_reports;
create trigger set_saved_reports_updated_at before update on public.saved_reports
for each row execute function public.set_updated_at();

-- Initial business vocabulary based on the current ERP schema.
insert into public.semantic_metrics (metric_key, zh_name, en_name, domain, source_tables, expression_hint, result_type)
values
  ('sales_amount', '销售额', 'Sales Amount', 'sales', array['sales_orders'], 'sum(sales_orders.total_amount)', 'currency'),
  ('sales_order_count', '销售订单数', 'Sales Order Count', 'sales', array['sales_orders'], 'count(distinct sales_orders.id)', 'number'),
  ('sales_quantity', '销售数量', 'Sales Quantity', 'sales', array['sales_order_items'], 'sum(sales_order_items.quantity)', 'quantity'),
  ('estimated_gross_profit', '估算毛利', 'Estimated Gross Profit', 'sales', array['sales_order_items', 'products'], 'sum(sales_order_items.line_amount - sales_order_items.quantity * products.cost_price)', 'currency'),
  ('purchase_amount', '采购金额', 'Purchase Amount', 'purchase', array['purchase_order_items'], 'sum(purchase_order_items.line_amount)', 'currency'),
  ('purchase_quantity', '采购数量', 'Purchase Quantity', 'purchase', array['purchase_order_items'], 'sum(purchase_order_items.quantity)', 'quantity'),
  ('stock_quantity', '当前库存', 'Current Stock', 'inventory', array['inventory'], 'inventory.quantity', 'quantity'),
  ('low_stock_item_count', '低库存商品数', 'Low Stock Item Count', 'inventory', array['inventory', 'products'], 'count where inventory.quantity < products.min_stock', 'number'),
  ('inbound_quantity', '入库数量', 'Inbound Quantity', 'inventory', array['stock_movements'], 'sum positive stock_movements.quantity_change', 'quantity'),
  ('outbound_quantity', '出库数量', 'Outbound Quantity', 'inventory', array['stock_movements'], 'sum absolute negative stock_movements.quantity_change', 'quantity')
on conflict (metric_key) do update set
  zh_name = excluded.zh_name,
  en_name = excluded.en_name,
  domain = excluded.domain,
  source_tables = excluded.source_tables,
  expression_hint = excluded.expression_hint,
  result_type = excluded.result_type;

insert into public.semantic_dimensions (dimension_key, zh_name, en_name, domain, source_tables, expression_hint, value_type)
values
  ('sales_order_date', '销售订单日期', 'Sales Order Date', 'sales', array['sales_orders'], 'sales_orders.order_date', 'timestamp'),
  ('purchase_order_date', '采购订单日期', 'Purchase Order Date', 'purchase', array['purchase_orders'], 'purchase_orders.order_date', 'date'),
  ('product', '商品', 'Product', 'cross_domain', array['products'], 'products.id, products.sku, products.name, products.zh_name', 'text'),
  ('product_category', '商品分类', 'Product Category', 'cross_domain', array['products'], 'products.category', 'text'),
  ('customer', '客户', 'Customer', 'sales', array['customers'], 'customers.id, customers.name, customers.zh_name', 'text'),
  ('customer_country', '客户国家', 'Customer Country', 'sales', array['customers'], 'customers.country', 'text'),
  ('customer_city', '客户城市', 'Customer City', 'sales', array['customers'], 'customers.city', 'text'),
  ('supplier', '供应商', 'Supplier', 'purchase', array['suppliers'], 'suppliers.id, suppliers.name, suppliers.zh_name', 'text'),
  ('sales_order_status', '销售订单状态', 'Sales Order Status', 'sales', array['sales_orders'], 'sales_orders.status', 'status'),
  ('purchase_order_status', '采购订单状态', 'Purchase Order Status', 'purchase', array['purchase_orders'], 'purchase_orders.status', 'status'),
  ('stock_movement_date', '库存流水日期', 'Stock Movement Date', 'inventory', array['stock_movements'], 'stock_movements.created_at', 'timestamp'),
  ('stock_movement_type', '库存移动类型', 'Stock Movement Type', 'inventory', array['stock_movements'], 'stock_movements.movement_type', 'status')
on conflict (dimension_key) do update set
  zh_name = excluded.zh_name,
  en_name = excluded.en_name,
  domain = excluded.domain,
  source_tables = excluded.source_tables,
  expression_hint = excluded.expression_hint,
  value_type = excluded.value_type;

insert into public.semantic_relationships (relationship_key, zh_name, en_name, left_table, right_table, join_type, join_condition_hint)
values
  ('sales_orders_customers', '销售订单到客户', 'Sales Orders to Customers', 'sales_orders', 'customers', 'left', 'sales_orders.customer_id = customers.id'),
  ('sales_orders_items', '销售订单到销售明细', 'Sales Orders to Sales Items', 'sales_orders', 'sales_order_items', 'inner', 'sales_order_items.sales_order_id = sales_orders.id'),
  ('sales_items_products', '销售明细到商品', 'Sales Items to Products', 'sales_order_items', 'products', 'inner', 'sales_order_items.product_id = products.id'),
  ('purchase_orders_suppliers', '采购订单到供应商', 'Purchase Orders to Suppliers', 'purchase_orders', 'suppliers', 'left', 'purchase_orders.supplier_id = suppliers.id'),
  ('purchase_orders_items', '采购订单到采购明细', 'Purchase Orders to Purchase Items', 'purchase_orders', 'purchase_order_items', 'inner', 'purchase_order_items.purchase_order_id = purchase_orders.id'),
  ('purchase_items_products', '采购明细到商品', 'Purchase Items to Products', 'purchase_order_items', 'products', 'inner', 'purchase_order_items.product_id = products.id'),
  ('products_inventory', '商品到当前库存', 'Products to Inventory', 'products', 'inventory', 'left', 'inventory.product_id = products.id'),
  ('products_stock_movements', '商品到库存流水', 'Products to Stock Movements', 'products', 'stock_movements', 'inner', 'stock_movements.product_id = products.id')
on conflict (relationship_key) do update set
  zh_name = excluded.zh_name,
  en_name = excluded.en_name,
  left_table = excluded.left_table,
  right_table = excluded.right_table,
  join_type = excluded.join_type,
  join_condition_hint = excluded.join_condition_hint;

insert into public.semantic_examples (example_key, zh_question, en_question, query_plan)
values
  ('sales_trend_month', '查看本月每日销售额', 'Show daily sales for this month', '{"metrics":["sales_amount"],"dimensions":["sales_order_date"],"filters":[{"field":"sales_order_status","operator":"=","value":"confirmed"}],"visualization":"line"}'::jsonb),
  ('customer_ranking_month', '本月客户销售排行', 'Rank customers by sales this month', '{"metrics":["sales_amount"],"dimensions":["customer"],"filters":[{"field":"sales_order_status","operator":"=","value":"confirmed"}],"order_by":[{"metric":"sales_amount","direction":"desc"}],"limit":20,"visualization":"bar"}'::jsonb),
  ('low_stock_products', '哪些商品需要补货', 'Which products need replenishment', '{"metrics":["stock_quantity"],"dimensions":["product","product_category"],"filters":[{"type":"stock_below_minimum"}],"visualization":"table"}'::jsonb),
  ('purchase_trend_month', '查看本月采购金额', 'Show purchase amount for this month', '{"metrics":["purchase_amount"],"dimensions":["purchase_order_date"],"filters":[{"field":"purchase_order_status","operator":"=","value":"confirmed"}],"visualization":"line"}'::jsonb)
on conflict (example_key) do update set
  zh_question = excluded.zh_question,
  en_question = excluded.en_question,
  query_plan = excluded.query_plan;

insert into public.query_intents (intent_key, title, zh_title, description, zh_description, example_phrases, query_plan_template, parameter_schema, allowed_roles, status)
values
  ('sales_trend', 'Sales Trend', '销售趋势', 'Confirmed sales by date.', '按日期汇总已确认销售额。', '["销售趋势", "查看本月每日销售额"]'::jsonb, '{"metrics":["sales_amount"],"dimensions":["sales_order_date"],"filters":[{"field":"sales_order_status","operator":"=","value":"confirmed"}],"visualization":"line"}'::jsonb, '[{"name":"date_range","type":"date_range","required":true}]'::jsonb, array['owner','manager'], 'active'),
  ('customer_sales_ranking', 'Customer Sales Ranking', '客户销售排行', 'Rank customers by confirmed sales amount.', '按已确认销售额排行客户。', '["客户销售排行", "哪个客户销售额最高"]'::jsonb, '{"metrics":["sales_amount"],"dimensions":["customer"],"filters":[{"field":"sales_order_status","operator":"=","value":"confirmed"}],"order_by":[{"metric":"sales_amount","direction":"desc"}],"limit":20,"visualization":"bar"}'::jsonb, '[{"name":"date_range","type":"date_range","required":true},{"name":"limit","type":"integer","default":20}]'::jsonb, array['owner','manager'], 'active'),
  ('low_stock_products', 'Low Stock Products', '低库存商品', 'Show products below their minimum stock.', '显示当前库存低于最低库存的商品。', '["低库存商品", "哪些商品需要补货"]'::jsonb, '{"metrics":["stock_quantity"],"dimensions":["product","product_category"],"filters":[{"type":"stock_below_minimum"}],"visualization":"table"}'::jsonb, '[]'::jsonb, array['owner','manager'], 'active'),
  ('purchase_trend', 'Purchase Trend', '采购趋势', 'Confirmed purchase amount by date.', '按日期汇总已确认采购金额。', '["采购趋势", "查看本月采购金额"]'::jsonb, '{"metrics":["purchase_amount"],"dimensions":["purchase_order_date"],"filters":[{"field":"purchase_order_status","operator":"=","value":"confirmed"}],"visualization":"line"}'::jsonb, '[{"name":"date_range","type":"date_range","required":true}]'::jsonb, array['owner','manager'], 'active')
on conflict (intent_key) do update set
  title = excluded.title,
  zh_title = excluded.zh_title,
  description = excluded.description,
  zh_description = excluded.zh_description,
  example_phrases = excluded.example_phrases,
  query_plan_template = excluded.query_plan_template,
  parameter_schema = excluded.parameter_schema,
  allowed_roles = excluded.allowed_roles,
  status = excluded.status;

alter table public.semantic_metrics enable row level security;
alter table public.semantic_dimensions enable row level security;
alter table public.semantic_relationships enable row level security;
alter table public.semantic_examples enable row level security;
alter table public.query_intents enable row level security;
alter table public.query_intent_proposals enable row level security;
alter table public.query_runs enable row level security;
alter table public.saved_reports enable row level security;
alter table public.report_versions enable row level security;

drop policy if exists "owner manager read semantic metrics" on public.semantic_metrics;
drop policy if exists "owner manages semantic metrics" on public.semantic_metrics;
drop policy if exists "owner manager read semantic dimensions" on public.semantic_dimensions;
drop policy if exists "owner manages semantic dimensions" on public.semantic_dimensions;
drop policy if exists "owner manager read semantic relationships" on public.semantic_relationships;
drop policy if exists "owner manages semantic relationships" on public.semantic_relationships;
drop policy if exists "owner manager read semantic examples" on public.semantic_examples;
drop policy if exists "owner manages semantic examples" on public.semantic_examples;
drop policy if exists "owner manager read active query intents" on public.query_intents;
drop policy if exists "owner manages query intents" on public.query_intents;
drop policy if exists "users read own proposals or owner reviews" on public.query_intent_proposals;
drop policy if exists "owner manager create proposals" on public.query_intent_proposals;
drop policy if exists "owner reviews proposals" on public.query_intent_proposals;
drop policy if exists "users read own query runs or owner reads all" on public.query_runs;
drop policy if exists "owner manager read saved reports" on public.saved_reports;
drop policy if exists "owner manager create saved reports" on public.saved_reports;
drop policy if exists "owners or creators update saved reports" on public.saved_reports;
drop policy if exists "owner manager read report versions" on public.report_versions;

create policy "owner manager read semantic metrics" on public.semantic_metrics for select to authenticated
using (public.is_active_user() and public.has_role(array['owner', 'manager']));
create policy "owner manages semantic metrics" on public.semantic_metrics for all to authenticated
using (public.has_role(array['owner'])) with check (public.has_role(array['owner']));

create policy "owner manager read semantic dimensions" on public.semantic_dimensions for select to authenticated
using (public.is_active_user() and public.has_role(array['owner', 'manager']));
create policy "owner manages semantic dimensions" on public.semantic_dimensions for all to authenticated
using (public.has_role(array['owner'])) with check (public.has_role(array['owner']));

create policy "owner manager read semantic relationships" on public.semantic_relationships for select to authenticated
using (public.is_active_user() and public.has_role(array['owner', 'manager']));
create policy "owner manages semantic relationships" on public.semantic_relationships for all to authenticated
using (public.has_role(array['owner'])) with check (public.has_role(array['owner']));

create policy "owner manager read semantic examples" on public.semantic_examples for select to authenticated
using (public.is_active_user() and public.has_role(array['owner', 'manager']));
create policy "owner manages semantic examples" on public.semantic_examples for all to authenticated
using (public.has_role(array['owner'])) with check (public.has_role(array['owner']));

create policy "owner manager read active query intents" on public.query_intents for select to authenticated
using (public.is_active_user() and status = 'active' and public.has_role(allowed_roles));
create policy "owner manages query intents" on public.query_intents for all to authenticated
using (public.has_role(array['owner'])) with check (public.has_role(array['owner']));

create policy "users read own proposals or owner reviews" on public.query_intent_proposals for select to authenticated
using (public.is_active_user() and (submitted_by = auth.uid() or public.has_role(array['owner'])));
create policy "owner manager create proposals" on public.query_intent_proposals for insert to authenticated
with check (public.has_role(array['owner', 'manager']) and submitted_by = auth.uid());
create policy "owner reviews proposals" on public.query_intent_proposals for update to authenticated
using (public.has_role(array['owner'])) with check (public.has_role(array['owner']));

create policy "users read own query runs or owner reads all" on public.query_runs for select to authenticated
using (public.is_active_user() and (created_by = auth.uid() or public.has_role(array['owner'])));

create policy "owner manager read saved reports" on public.saved_reports for select to authenticated
using (public.is_active_user() and is_active and public.has_role(allowed_roles));
create policy "owner manager create saved reports" on public.saved_reports for insert to authenticated
with check (public.has_role(array['owner', 'manager']) and created_by = auth.uid());
create policy "owners or creators update saved reports" on public.saved_reports for update to authenticated
using (public.has_role(array['owner']) or created_by = auth.uid())
with check (public.has_role(array['owner']) or created_by = auth.uid());

create policy "owner manager read report versions" on public.report_versions for select to authenticated
using (public.is_active_user() and public.has_role(array['owner', 'manager']));

commit;
