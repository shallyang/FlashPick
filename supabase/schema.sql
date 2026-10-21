-- 闪拾 FlashPick · Phase 2 云同步库表（Supabase / PostgreSQL）
-- 设计目标：按账号隔离（RLS），updated_at LWW 冲突策略，软删除便于多端收敛。

create extension if not exists "pgcrypto";

create table if not exists public.todos (
  id uuid primary key,                           -- 客户端生成的 UUID v4，与本地 SQLite 同 id
  user_id uuid not null references auth.users (id) on delete cascade,
  text text not null,
  done boolean not null default false,
  done_at timestamptz,
  source text not null default 'hotkey',         -- hotkey | panel | clipboard | menu
  deleted boolean not null default false,        -- 软删除
  device_id text,                                -- 产生该变更的设备
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()  -- LWW 时间戳（客户端上传，服务端触发器兜底）
);

create index if not exists todos_user_updated_idx
  on public.todos (user_id, updated_at desc);

-- updated_at 兜底：若客户端未带时间戳则服务端打点
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  if new.updated_at is null or new.updated_at < old.updated_at then
    new.updated_at := now();
  end if;
  return new;
end $$;

drop trigger if exists todos_touch_updated_at on public.todos;
create trigger todos_touch_updated_at
  before update on public.todos
  for each row execute function public.touch_updated_at();

-- RLS：只能读写自己的待办
alter table public.todos enable row level security;

drop policy if exists "todos_select_own" on public.todos;
create policy "todos_select_own" on public.todos
  for select using (auth.uid() = user_id);

drop policy if exists "todos_insert_own" on public.todos;
create policy "todos_insert_own" on public.todos
  for insert with check (auth.uid() = user_id);

drop policy if exists "todos_update_own" on public.todos;
create policy "todos_update_own" on public.todos
  for update using (auth.uid() = user_id);

drop policy if exists "todos_delete_own" on public.todos;
create policy "todos_delete_own" on public.todos
  for delete using (auth.uid() = user_id);

-- Realtime：开启表级广播，客户端订阅后多端秒级收敛
alter publication supabase_realtime add table public.todos;

-- 客户端同步协议（约定）
-- 1. 拉取：select * from todos where user_id = me and updated_at > :last_sync
-- 2. 推送：upsert (id) 本地 updated_at > 远端 updated_at 的行
-- 3. 冲突：以 updated_at 更大者为准（LWW）；deleted=true 的行本地也置为删除
