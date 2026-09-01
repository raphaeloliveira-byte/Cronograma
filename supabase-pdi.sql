-- =====================================================================
-- RODE ESTE ARQUIVO NO SUPABASE PARA LIGAR A ABA PDI.
--
-- Como fazer:
--   1. Abra seu projeto no Supabase
--   2. Menu da esquerda > SQL Editor > New query
--   3. Copie TODO o conteúdo deste arquivo, cole lá e clique em Run
--
-- Pode rodar mais de uma vez sem problema. NÃO mexe na sua senha de
-- admin e NÃO apaga nada do cronograma que já existe.
-- =====================================================================

-- 1) Cria o lugar onde o PDI fica guardado (uma coluna nova na tabela).
alter table public.cronograma_state
  add column if not exists pdi jsonb not null default '{"points":[]}'::jsonb;

-- 2) Cria a função que salva o PDI conferindo a senha de admin.
--    É separada da do cronograma, então salvar o PDI não mexe nas tarefas.
create or replace function public.update_cronograma_pdi(p_password text, p_pdi jsonb)
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
  set pdi = coalesce(p_pdi, '{"points":[]}'::jsonb),
      updated_at = now()
  where id = 1;
end;
$$;

-- 3) Libera a função para as páginas chamarem (a senha continua sendo exigida).
revoke all on function public.update_cronograma_pdi(text, jsonb) from public;
grant execute on function public.update_cronograma_pdi(text, jsonb) to anon, authenticated;