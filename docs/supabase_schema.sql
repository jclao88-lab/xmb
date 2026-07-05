-- Supabase/Postgres schema for first-version street shop ERP.
-- Run this file in Supabase SQL Editor, or convert it into a migration.

begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  zh_display_name text,
  phone text,
  role text not null default 'cashier'
    check (role in ('owner', 'manager', 'cashier')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  zh_name text,
  contact_name text,
  phone text,
  country text,
  province text,
  city text,
  address text,
  note text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  zh_name text,
  phone text,
  country text,
  province text,
  city text,
  address text,
  note text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  barcode text unique,
  name text not null,
  zh_name text,
  category text,
  specification text,
  unit text not null default 'pcs',
  cost_price numeric(12, 2) not null default 0 check (cost_price >= 0),
  sale_price numeric(12, 2) not null default 0 check (sale_price >= 0),
  min_stock numeric(12, 3) not null default 0 check (min_stock >= 0),
  default_order_quantity numeric(12, 3) check (default_order_quantity is null or default_order_quantity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory (
  product_id uuid primary key references public.products(id) on delete restrict,
  quantity numeric(12, 3) not null default 0 check (quantity >= 0),
  last_movement_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null unique,
  supplier_id uuid references public.suppliers(id) on delete restrict,
  status text not null default 'draft'
    check (status in ('draft', 'confirmed', 'cancelled')),
  order_date date not null default current_date,
  total_amount numeric(12, 2) not null default 0 check (total_amount >= 0),
  note text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(12, 3) not null check (quantity > 0),
  received_quantity numeric(12, 3) not null default 0
    check (received_quantity >= 0 and received_quantity <= quantity),
  is_received_complete boolean not null default false,
  unit_cost numeric(12, 2) not null check (unit_cost >= 0),
  line_amount numeric(12, 2) not null check (line_amount >= 0),
  received_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null unique,
  customer_id uuid references public.customers(id) on delete set null,
  status text not null default 'draft'
    check (status in ('draft', 'confirmed', 'cancelled')),
  order_date timestamptz not null default now(),
  subtotal_amount numeric(12, 2) not null default 0 check (subtotal_amount >= 0),
  discount_amount numeric(12, 2) not null default 0 check (discount_amount >= 0),
  total_amount numeric(12, 2) not null default 0 check (total_amount >= 0),
  payment_method text,
  note text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  sales_order_id uuid not null references public.sales_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(12, 3) not null check (quantity > 0),
  shipped_quantity numeric(12, 3) not null default 0
    check (shipped_quantity >= 0 and shipped_quantity <= quantity),
  is_shipped_complete boolean not null default false,
  unit_price numeric(12, 2) not null check (unit_price >= 0),
  discount_amount numeric(12, 2) not null default 0 check (discount_amount >= 0),
  line_amount numeric(12, 2) not null check (line_amount >= 0),
  shipped_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null
    check (movement_type in ('purchase_in', 'sale_out', 'adjustment', 'return_in', 'return_out', '101', '501', '601', '603')),
  quantity_change numeric(12, 3) not null,
  quantity_after numeric(12, 3) not null check (quantity_after >= 0),
  reference_type text not null
    check (reference_type in ('purchase_order', 'sales_order', 'manual_adjustment')),
  reference_id uuid,
  reference_item_id uuid,
  reference_order_no text,
  reference_line_no integer check (reference_line_no is null or reference_line_no > 0),
  note text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_suppliers_name on public.suppliers(name);
create index if not exists idx_customers_phone on public.customers(phone);
create index if not exists idx_products_name on public.products(name);
create index if not exists idx_products_barcode on public.products(barcode);
create index if not exists idx_purchase_orders_supplier on public.purchase_orders(supplier_id);
create index if not exists idx_purchase_order_items_order on public.purchase_order_items(purchase_order_id);
create index if not exists idx_purchase_order_items_product on public.purchase_order_items(product_id);
create index if not exists idx_sales_orders_customer on public.sales_orders(customer_id);
create index if not exists idx_sales_order_items_order on public.sales_order_items(sales_order_id);
create index if not exists idx_sales_order_items_product on public.sales_order_items(product_id);
create index if not exists idx_stock_movements_product on public.stock_movements(product_id);
create index if not exists idx_stock_movements_reference_order on public.stock_movements(reference_type, reference_order_no);
create index if not exists idx_stock_movements_reference_item on public.stock_movements(reference_item_id);
create index if not exists idx_stock_movements_created_at on public.stock_movements(created_at);

drop trigger if exists set_users_updated_at on public.users;
create trigger set_users_updated_at
before update on public.users
for each row execute function public.set_updated_at();

drop trigger if exists set_suppliers_updated_at on public.suppliers;
create trigger set_suppliers_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

drop trigger if exists set_customers_updated_at on public.customers;
create trigger set_customers_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

drop trigger if exists set_products_updated_at on public.products;
create trigger set_products_updated_at
before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists set_inventory_updated_at on public.inventory;
create trigger set_inventory_updated_at
before update on public.inventory
for each row execute function public.set_updated_at();

drop trigger if exists set_purchase_orders_updated_at on public.purchase_orders;
create trigger set_purchase_orders_updated_at
before update on public.purchase_orders
for each row execute function public.set_updated_at();

drop trigger if exists set_sales_orders_updated_at on public.sales_orders;
create trigger set_sales_orders_updated_at
before update on public.sales_orders
for each row execute function public.set_updated_at();

alter table public.users enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;
alter table public.stock_movements enable row level security;

create policy "authenticated users can read users"
on public.users for select
to authenticated
using (true);

create policy "users can update own profile"
on public.users for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy "authenticated users can read suppliers"
on public.suppliers for select
to authenticated
using (true);

create policy "authenticated users can write suppliers"
on public.suppliers for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read customers"
on public.customers for select
to authenticated
using (true);

create policy "authenticated users can write customers"
on public.customers for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read products"
on public.products for select
to authenticated
using (true);

create policy "authenticated users can write products"
on public.products for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read inventory"
on public.inventory for select
to authenticated
using (true);

create policy "authenticated users can write inventory"
on public.inventory for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read purchase orders"
on public.purchase_orders for select
to authenticated
using (true);

create policy "authenticated users can write purchase orders"
on public.purchase_orders for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read purchase order items"
on public.purchase_order_items for select
to authenticated
using (true);

create policy "authenticated users can write purchase order items"
on public.purchase_order_items for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read sales orders"
on public.sales_orders for select
to authenticated
using (true);

create policy "authenticated users can write sales orders"
on public.sales_orders for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read sales order items"
on public.sales_order_items for select
to authenticated
using (true);

create policy "authenticated users can write sales order items"
on public.sales_order_items for all
to authenticated
using (true)
with check (true);

create policy "authenticated users can read stock movements"
on public.stock_movements for select
to authenticated
using (true);

create policy "authenticated users can write stock movements"
on public.stock_movements for all
to authenticated
using (true)
with check (true);

commit;
