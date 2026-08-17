-- CartSense cloud sync tables for Supabase.
-- Run this once in Supabase Dashboard > SQL Editor.

create table if not exists public.cartsense_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  receipt_id text not null,
  store text,
  purchased_at timestamptz,
  total numeric,
  payload jsonb not null default '{}'::jsonb,
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, receipt_id)
);

create table if not exists public.cartsense_shopping_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null,
  name text,
  checked boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

create table if not exists public.cartsense_user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.cartsense_receipts enable row level security;
alter table public.cartsense_shopping_items enable row level security;
alter table public.cartsense_user_settings enable row level security;

drop policy if exists "CartSense users manage own receipts"
  on public.cartsense_receipts;
create policy "CartSense users manage own receipts"
  on public.cartsense_receipts
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "CartSense users manage own shopping items"
  on public.cartsense_shopping_items;
create policy "CartSense users manage own shopping items"
  on public.cartsense_shopping_items
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "CartSense users manage own settings"
  on public.cartsense_user_settings;
create policy "CartSense users manage own settings"
  on public.cartsense_user_settings
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists cartsense_receipts_user_purchased_idx
  on public.cartsense_receipts(user_id, purchased_at desc);

create index if not exists cartsense_shopping_items_user_updated_idx
  on public.cartsense_shopping_items(user_id, updated_at desc);
