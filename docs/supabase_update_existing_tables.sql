-- Update existing Supabase tables to the latest local schema.
-- Safe to run more than once. It only adds missing columns/constraints.

begin;

alter table public.users
add column if not exists zh_display_name text;

alter table public.suppliers
add column if not exists zh_name text,
add column if not exists country text,
add column if not exists province text,
add column if not exists city text;

alter table public.customers
add column if not exists zh_name text,
add column if not exists country text,
add column if not exists province text,
add column if not exists city text;

alter table public.products
add column if not exists zh_name text,
add column if not exists default_order_quantity numeric(12, 3);

alter table public.purchase_order_items
add column if not exists received_date date,
add column if not exists received_quantity numeric(12, 3) not null default 0,
add column if not exists is_received_complete boolean not null default false;

alter table public.sales_order_items
add column if not exists shipped_date date,
add column if not exists shipped_quantity numeric(12, 3) not null default 0,
add column if not exists is_shipped_complete boolean not null default false;

alter table public.stock_movements
add column if not exists reference_item_id uuid,
add column if not exists reference_order_no text,
add column if not exists reference_line_no integer;

update public.purchase_order_items
set received_quantity = 0
where received_quantity is null;

update public.purchase_order_items
set is_received_complete = false
where is_received_complete is null;

alter table public.purchase_order_items
alter column received_quantity set default 0,
alter column received_quantity set not null,
alter column is_received_complete set default false,
alter column is_received_complete set not null;

update public.sales_order_items
set shipped_quantity = 0
where shipped_quantity is null;

update public.sales_order_items
set is_shipped_complete = false
where is_shipped_complete is null;

alter table public.sales_order_items
alter column shipped_quantity set default 0,
alter column shipped_quantity set not null,
alter column is_shipped_complete set default false,
alter column is_shipped_complete set not null;

alter table public.sales_orders
drop constraint if exists sales_orders_status_check;

update public.sales_orders
set status = 'confirmed'
where status = 'paid';

update public.sales_orders
set status = 'cancelled'
where status = 'refunded';

alter table public.sales_orders
add constraint sales_orders_status_check
check (status in ('draft', 'confirmed', 'cancelled'));

alter table public.stock_movements
drop constraint if exists stock_movements_movement_type_check;

alter table public.stock_movements
add constraint stock_movements_movement_type_check
check (movement_type in ('purchase_in', 'sale_out', 'adjustment', 'return_in', 'return_out', '101', '501', '601', '603'));

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchase_order_items_received_quantity_range'
      and conrelid = 'public.purchase_order_items'::regclass
  ) then
    alter table public.purchase_order_items
    add constraint purchase_order_items_received_quantity_range
    check (received_quantity >= 0 and received_quantity <= quantity);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_order_items_shipped_quantity_range'
      and conrelid = 'public.sales_order_items'::regclass
  ) then
    alter table public.sales_order_items
    add constraint sales_order_items_shipped_quantity_range
    check (shipped_quantity >= 0 and shipped_quantity <= quantity);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'stock_movements_reference_line_no_positive'
      and conrelid = 'public.stock_movements'::regclass
  ) then
    alter table public.stock_movements
    add constraint stock_movements_reference_line_no_positive
    check (reference_line_no is null or reference_line_no > 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_default_order_quantity_positive'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
    add constraint products_default_order_quantity_positive
    check (default_order_quantity is null or default_order_quantity > 0);
  end if;
end $$;

create index if not exists idx_stock_movements_reference_order
on public.stock_movements(reference_type, reference_order_no);

create index if not exists idx_stock_movements_reference_item
on public.stock_movements(reference_item_id);

drop policy if exists "owner manager read purchase orders" on public.purchase_orders;
drop policy if exists "owner manager read purchase order items" on public.purchase_order_items;
drop policy if exists "active users read purchase orders" on public.purchase_orders;
drop policy if exists "active users read purchase order items" on public.purchase_order_items;

create policy "active users read purchase orders"
on public.purchase_orders
for select
to authenticated
using (public.is_active_user());

create policy "active users read purchase order items"
on public.purchase_order_items
for select
to authenticated
using (public.is_active_user());

commit;
