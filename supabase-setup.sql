-- Execute este script inteiro no SQL Editor do seu projeto Supabase (Database > SQL Editor > New query).
-- Antes de rodar, troque 'TROQUE_ESTA_SENHA' pela senha que você vai usar para editar o cronograma em /adm.

create extension if not exists pgcrypto;

-- Tabela com o estado do cronograma (uma única linha, id = 1)
create table if not exists public.cronograma_state (
  id int primary key default 1,
  config jsonb,
  tasks jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  constraint cronograma_state_singleton check (id = 1)
);

insert into public.cronograma_state (id, config, tasks)
values (1, null, '[]'::jsonb)
on conflict (id) do nothing;

alter table public.cronograma_state enable row level security;

-- Leitura pública (a página do supervisor lê direto, sem senha)
drop policy if exists "cronograma_state select" on public.cronograma_state;
create policy "cronograma_state select"
  on public.cronograma_state
  for select
  using (true);

-- Sem policy de insert/update/delete: ninguém escreve direto na tabela via API,
-- só através da função abaixo, que confere a senha.

-- Tabela separada para guardar o hash da senha de admin.
-- RLS ativado e SEM nenhuma policy = inacessível via API pública, mesmo para leitura.
create table if not exists public._cronograma_admin (
  id int primary key default 1,
  password_hash text not null,
  constraint cronograma_admin_singleton check (id = 1)
);
alter table public._cronograma_admin enable row level security;

insert into public._cronograma_admin (id, password_hash)
values (1, crypt('TROQUE_ESTA_SENHA', gen_salt('bf')))
on conflict (id) do update set password_hash = excluded.password_hash;

-- Função que valida a senha e só então atualiza o cronograma.
-- security definer = roda com o dono da função (bypassa a RLS internamente),
-- então ela consegue ler a senha guardada e escrever na tabela pública.
create or replace function public.update_cronograma_state(p_password text, p_config jsonb, p_tasks jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
begin
  select password_hash into v_hash from public._cronograma_admin where id = 1;
  if v_hash is null or crypt(p_password, v_hash) <> v_hash then
    raise exception 'senha inválida';
  end if;

  update public.cronograma_state
  set config = p_config,
      tasks = p_tasks,
      updated_at = now()
  where id = 1;
end;
$$;

revoke all on function public.update_cronograma_state(text, jsonb, jsonb) from public;
grant execute on function public.update_cronograma_state(text, jsonb, jsonb) to anon, authenticated;

-- Habilita atualizações em tempo real para essa tabela (o link do supervisor
-- atualiza sozinho quando você marca algo, sem precisar recarregar a página).
alter publication supabase_realtime add table public.cronograma_state;
