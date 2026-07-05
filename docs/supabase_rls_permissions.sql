-- Role-based RLS permissions for the street shop ERP.
-- Run this in Supabase SQL Editor after tables and public.users are created.
--
-- Roles are stored in public.users.role:
--   owner   : full business access and user management
--   manager : manages products, suppliers, customers, purchases, inventory
--   cashier : creates sales, ships goods, receives goods, and reads common business data

begin;

create or replace function public.current_user_role()
returns text
language sql
security definer
set search_path = public
as $$
  select role
  from public.users
  where id = auth.uid()
    and is_active = true
  limit 1
$$;

create or replace function public.is_active_user()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users
    where id = auth.uid()
      and is_active = true
  )
$$;

create or replace function public.has_role(allowed_roles text[])
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.current_user_role() = any(allowed_roles)
$$;

grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.has_role(text[]) to authenticated;

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

grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.users,
  public.suppliers,
  public.customers,
  public.products,
  public.inventory,
  public.purchase_orders,
  public.purchase_order_items,
  public.sales_orders,
  public.sales_order_items,
  public.stock_movements
to authenticated;

drop policy if exists "authenticated users can read users" on public.users;
drop policy if exists "users can update own profile" on public.users;
drop policy if exists "authenticated users can read suppliers" on public.suppliers;
drop policy if exists "authenticated users can write suppliers" on public.suppliers;
drop policy if exists "authenticated users can read customers" on public.customers;
drop policy if exists "authenticated users can write customers" on public.customers;
drop policy if exists "authenticated users can read products" on public.products;
drop policy if exists "authenticated users can write products" on public.products;
drop policy if exists "authenticated users can read inventory" on public.inventory;
drop policy if exists "authenticated users can write inventory" on public.inventory;
drop policy if exists "authenticated users can read purchase orders" on public.purchase_orders;
drop policy if exists "authenticated users can write purchase orders" on public.purchase_orders;
drop policy if exists "authenticated users can read purchase order items" on public.purchase_order_items;
drop policy if exists "authenticated users can write purchase order items" on public.purchase_order_items;
drop policy if exists "authenticated users can read sales orders" on public.sales_orders;
drop policy if exists "authenticated users can write sales orders" on public.sales_orders;
drop policy if exists "authenticated users can read sales order items" on public.sales_order_items;
drop policy if exists "authenticated users can write sales order items" on public.sales_order_items;
drop policy if exists "authenticated users can read stock movements" on public.stock_movements;
drop policy if exists "authenticated users can write stock movements" on public.stock_movements;

drop policy if exists "users read own or manager read users" on public.users;
drop policy if exists "owner manages users" on public.users;
drop policy if exists "active users read suppliers" on public.suppliers;
drop policy if exists "owner manager write suppliers" on public.suppliers;
drop policy if exists "active users read customers" on public.customers;
drop policy if exists "owner manager write customers" on public.customers;
drop policy if exists "active users read products" on public.products;
drop policy if exists "owner manager write products" on public.products;
drop policy if exists "active users read inventory" on public.inventory;
drop policy if exists "owner manager write inventory" on public.inventory;
drop policy if exists "active users write inventory" on public.inventory;
drop policy if exists "owner manager read purchase orders" on public.purchase_orders;
drop policy if exists "owner manager write purchase orders" on public.purchase_orders;
drop policy if exists "active users create purchase orders" on public.purchase_orders;
drop policy if exists "active users update purchase orders" on public.purchase_orders;
drop policy if exists "owner manager read purchase order items" on public.purchase_order_items;
drop policy if exists "owner manager write purchase order items" on public.purchase_order_items;
drop policy if exists "active users create purchase order items" on public.purchase_order_items;
drop policy if exists "active users update purchase order items" on public.purchase_order_items;
drop policy if exists "active users read purchase orders" on public.purchase_orders;
drop policy if exists "active users read purchase order items" on public.purchase_order_items;
drop policy if exists "active users read sales orders" on public.sales_orders;
drop policy if exists "active users create sales orders" on public.sales_orders;
drop policy if exists "owner manager update sales orders" on public.sales_orders;
drop policy if exists "owner manager delete sales orders" on public.sales_orders;
drop policy if exists "active users read sales order items" on public.sales_order_items;
drop policy if exists "active users create sales order items" on public.sales_order_items;
drop policy if exists "owner manager update sales order items" on public.sales_order_items;
drop policy if exists "active users update sales order items" on public.sales_order_items;
drop policy if exists "owner manager delete sales order items" on public.sales_order_items;
drop policy if exists "active users read stock movements" on public.stock_movements;
drop policy if exists "owner manager write stock movements" on public.stock_movements;
drop policy if exists "active users write stock movements" on public.stock_movements;

create policy "users read own or manager read users"
on public.users
for select
to authenticated
using (
  id = auth.uid()
  or public.has_role(array['owner', 'manager'])
);

create policy "owner manages users"
on public.users
for all
to authenticated
using (public.has_role(array['owner']))
with check (public.has_role(array['owner']));

create policy "active users read suppliers"
on public.suppliers
for select
to authenticated
using (public.is_active_user());

create policy "owner manager write suppliers"
on public.suppliers
for all
to authenticated
using (public.has_role(array['owner', 'manager']))
with check (public.has_role(array['owner', 'manager']));

create policy "active users read customers"
on public.customers
for select
to authenticated
using (public.is_active_user());

create policy "owner manager write customers"
on public.customers
for all
to authenticated
using (public.has_role(array['owner', 'manager']))
with check (public.has_role(array['owner', 'manager']));

create policy "active users read products"
on public.products
for select
to authenticated
using (public.is_active_user());

create policy "owner manager write products"
on public.products
for all
to authenticated
using (public.has_role(array['owner', 'manager']))
with check (public.has_role(array['owner', 'manager']));

create policy "active users read inventory"
on public.inventory
for select
to authenticated
using (public.is_active_user());

create policy "active users write inventory"
on public.inventory
for all
to authenticated
using (public.is_active_user())
with check (public.is_active_user());

create policy "active users read purchase orders"
on public.purchase_orders
for select
to authenticated
using (public.is_active_user());

create policy "active users create purchase orders"
on public.purchase_orders
for insert
to authenticated
with check (public.is_active_user());

create policy "active users update purchase orders"
on public.purchase_orders
for update
to authenticated
using (public.is_active_user())
with check (public.is_active_user());

create policy "active users read purchase order items"
on public.purchase_order_items
for select
to authenticated
using (public.is_active_user());

create policy "active users create purchase order items"
on public.purchase_order_items
for insert
to authenticated
with check (public.is_active_user());

create policy "active users update purchase order items"
on public.purchase_order_items
for update
to authenticated
using (public.is_active_user())
with check (public.is_active_user());

create policy "active users read sales orders"
on public.sales_orders
for select
to authenticated
using (public.is_active_user());

create policy "active users create sales orders"
on public.sales_orders
for insert
to authenticated
with check (public.is_active_user());

create policy "owner manager update sales orders"
on public.sales_orders
for update
to authenticated
using (public.has_role(array['owner', 'manager']))
with check (public.has_role(array['owner', 'manager']));

create policy "owner manager delete sales orders"
on public.sales_orders
for delete
to authenticated
using (public.has_role(array['owner', 'manager']));

create policy "active users read sales order items"
on public.sales_order_items
for select
to authenticated
using (public.is_active_user());

create policy "active users create sales order items"
on public.sales_order_items
for insert
to authenticated
with check (public.is_active_user());

create policy "active users update sales order items"
on public.sales_order_items
for update
to authenticated
using (public.is_active_user())
with check (public.is_active_user());

create policy "owner manager delete sales order items"
on public.sales_order_items
for delete
to authenticated
using (public.has_role(array['owner', 'manager']));

create policy "active users read stock movements"
on public.stock_movements
for select
to authenticated
using (public.is_active_user());

create policy "active users write stock movements"
on public.stock_movements
for all
to authenticated
using (public.is_active_user())
with check (public.is_active_user());

commit;
