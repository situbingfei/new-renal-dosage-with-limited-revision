-- Integrated cloud edition: keep the original UI, add Auth/RLS write protection and an atomic save RPC.
-- Prerequisite: public.drug_rules and public.drug_qr already exist.
-- Run in Supabase SQL Editor as the project owner/postgres.
-- This migration intentionally does NOT alter Supabase-managed storage.objects.
-- Configure the Storage bucket and admin-only INSERT/SELECT/DELETE policies in Dashboard -> Storage (see README).
-- This file does NOT create or grant an administrator; the allow-list starts empty.

begin;

do $$
begin
  if to_regclass('public.drug_rules') is null then
    raise exception 'Missing public.drug_rules. Run the initial read-only schema/seed first.';
  end if;
  if to_regclass('public.drug_qr') is null then
    raise exception 'Missing public.drug_qr. Run the initial read-only schema/seed first.';
  end if;
end;
$$;

-- Private administrator allow-list: do not expose the private schema through Data API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table if not exists private.renal_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);
alter table private.renal_admins enable row level security;
revoke all on table private.renal_admins from public, anon, authenticated;

-- SECURITY DEFINER checks only the current caller; no user-id argument is accepted.
create or replace function private.is_renal_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.renal_admins as a
    where a.user_id = (select auth.uid())
  );
$$;
revoke all on function private.is_renal_admin() from public, anon, authenticated;
grant execute on function private.is_renal_admin() to authenticated;

-- Safe status check for the maintenance page; reveals only the caller's own boolean status.
create or replace function public.is_renal_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.is_renal_admin();
$$;
revoke all on function public.is_renal_admin() from public, anon, authenticated;
grant execute on function public.is_renal_admin() to authenticated;

-- anon and authenticated can read. Only authenticated users receive table-level
-- write grants; the RLS policies below restrict those writes to the admin allow-list.
grant usage on schema public to anon, authenticated;
revoke all on table public.drug_rules, public.drug_qr from public, anon, authenticated;
grant select on table public.drug_rules, public.drug_qr to anon, authenticated;
grant insert, update, delete on table public.drug_rules, public.drug_qr to authenticated;

alter table public.drug_rules enable row level security;
alter table public.drug_qr enable row level security;

drop policy if exists "public read drug rules" on public.drug_rules;
create policy "public read drug rules"
  on public.drug_rules for select to anon, authenticated
  using (true);

drop policy if exists "public read QR index" on public.drug_qr;
create policy "public read QR index"
  on public.drug_qr for select to anon, authenticated
  using (true);

drop policy if exists "renal admins insert rules" on public.drug_rules;
create policy "renal admins insert rules"
  on public.drug_rules for insert to authenticated
  with check ((select private.is_renal_admin()));

drop policy if exists "renal admins update rules" on public.drug_rules;
create policy "renal admins update rules"
  on public.drug_rules for update to authenticated
  using ((select private.is_renal_admin()))
  with check ((select private.is_renal_admin()));

drop policy if exists "renal admins delete rules" on public.drug_rules;
create policy "renal admins delete rules"
  on public.drug_rules for delete to authenticated
  using ((select private.is_renal_admin()));

drop policy if exists "renal admins insert QR index" on public.drug_qr;
create policy "renal admins insert QR index"
  on public.drug_qr for insert to authenticated
  with check ((select private.is_renal_admin()));

drop policy if exists "renal admins update QR index" on public.drug_qr;
create policy "renal admins update QR index"
  on public.drug_qr for update to authenticated
  using ((select private.is_renal_admin()))
  with check ((select private.is_renal_admin()));

drop policy if exists "renal admins delete QR index" on public.drug_qr;
create policy "renal admins delete QR index"
  on public.drug_qr for delete to authenticated
  using ((select private.is_renal_admin()));

-- Private audit trail for rule and QR-index changes; written only by DB triggers.
create table if not exists private.renal_rule_audit (
  audit_id bigint generated always as identity primary key,
  changed_at timestamptz not null default now(),
  actor_user_id uuid,
  table_name text not null,
  row_id text not null,
  operation text not null check (operation in ('INSERT','UPDATE','DELETE')),
  old_data jsonb,
  new_data jsonb
);
alter table private.renal_rule_audit enable row level security;
revoke all on table private.renal_rule_audit from public, anon, authenticated;

create or replace function private.log_renal_rule_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_row_id text;
begin
  if tg_op in ('UPDATE','DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then v_new := to_jsonb(new); end if;
  v_row_id := coalesce(
    v_new->>'_id',
    v_old->>'_id',
    concat(coalesce(v_new->>'drug_id',v_old->>'drug_id',''), '||', coalesce(v_new->>'drug_name',v_old->>'drug_name',''))
  );
  insert into private.renal_rule_audit(actor_user_id,table_name,row_id,operation,old_data,new_data)
  values ((select auth.uid()), tg_table_schema||'.'||tg_table_name, coalesce(v_row_id,'unknown'), tg_op, v_old, v_new);
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function private.log_renal_rule_change() from public, anon, authenticated;

drop trigger if exists renal_rules_audit on public.drug_rules;
create trigger renal_rules_audit after insert or update or delete on public.drug_rules
for each row execute function private.log_renal_rule_change();
drop trigger if exists renal_qr_audit on public.drug_qr;
create trigger renal_qr_audit after insert or update or delete on public.drug_qr
for each row execute function private.log_renal_rule_change();


-- One transactional save endpoint used by the unchanged page's /api/db adapter.
-- RLS still applies (SECURITY INVOKER); the function also checks the admin allow-list.
create or replace function public.replace_renal_database(p_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_records jsonb;
  v_qr jsonb;
  v_count integer;
  v_distinct integer;
begin
  if not private.is_renal_admin() then
    raise exception using errcode = '42501', message = 'Only an allow-listed renal database administrator may save.';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'The save payload must be a JSON object.';
  end if;

  v_records := coalesce(p_payload -> 'records', '[]'::jsonb);
  v_qr := coalesce(p_payload -> 'qr', '{}'::jsonb);
  if jsonb_typeof(v_records) <> 'array' then
    raise exception using errcode = '22023', message = 'records must be a JSON array.';
  end if;
  if jsonb_typeof(v_qr) <> 'object' then
    raise exception using errcode = '22023', message = 'qr must be a JSON object.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_records) as e(item)
    where jsonb_typeof(e.item) <> 'object'
       or coalesce(btrim(e.item ->> '_id'), '') = ''
       or coalesce(btrim(e.item ->> 'drug_id'), '') = ''
       or coalesce(btrim(e.item ->> 'drug_name'), '') = ''
  ) then
    raise exception using errcode = '22023', message = 'Every dose rule must have _id, drug_id and drug_name.';
  end if;
  select count(*)::integer, count(distinct e.item ->> '_id')::integer
    into v_count, v_distinct
    from jsonb_array_elements(v_records) as e(item);
  if v_count <> v_distinct then
    raise exception using errcode = '22023', message = 'Dose rule IDs must be unique.';
  end if;

  delete from public.drug_rules as r
  where not exists (
    select 1 from jsonb_array_elements(v_records) as e(item)
    where e.item ->> '_id' = r._id
  );

  insert into public.drug_rules as existing (
    _id, drug_id, drug_name, renal_function_level, ccr_min, ccr_max, dose_unit,
    dose_value, dose_total_value, dose_description, adjustment_rule, special_notes, reference, sort_order
  )
  select
    btrim(e.item ->> '_id'),
    btrim(e.item ->> 'drug_id'),
    btrim(e.item ->> 'drug_name'),
    coalesce(e.item ->> 'renal_function_level', ''),
    coalesce(e.item ->> 'ccr_min', ''),
    coalesce(e.item ->> 'ccr_max', ''),
    coalesce(e.item ->> 'dose_unit', ''),
    coalesce(e.item ->> 'dose_value', ''),
    coalesce(e.item ->> 'dose_total_value', ''),
    coalesce(e.item ->> 'dose_description', ''),
    coalesce(e.item ->> 'adjustment_rule', ''),
    coalesce(e.item ->> 'special_notes', ''),
    coalesce(e.item ->> 'reference', ''),
    (e.ordinality - 1)::integer
  from jsonb_array_elements(v_records) with ordinality as e(item, ordinality)
  on conflict (_id) do update set
    drug_id = excluded.drug_id,
    drug_name = excluded.drug_name,
    renal_function_level = excluded.renal_function_level,
    ccr_min = excluded.ccr_min,
    ccr_max = excluded.ccr_max,
    dose_unit = excluded.dose_unit,
    dose_value = excluded.dose_value,
    dose_total_value = excluded.dose_total_value,
    dose_description = excluded.dose_description,
    adjustment_rule = excluded.adjustment_rule,
    special_notes = excluded.special_notes,
    reference = excluded.reference,
    sort_order = excluded.sort_order
  where (existing.drug_id, existing.drug_name, existing.renal_function_level, existing.ccr_min,
         existing.ccr_max, existing.dose_unit, existing.dose_value, existing.dose_total_value,
         existing.dose_description, existing.adjustment_rule, existing.special_notes, existing.reference, existing.sort_order)
    is distinct from
        (excluded.drug_id, excluded.drug_name, excluded.renal_function_level, excluded.ccr_min,
         excluded.ccr_max, excluded.dose_unit, excluded.dose_value, excluded.dose_total_value,
         excluded.dose_description, excluded.adjustment_rule, excluded.special_notes, excluded.reference, excluded.sort_order);

  delete from public.drug_qr as q
  where not exists (
    select 1
    from jsonb_each(v_qr) as e(key, value)
    where e.key = q.drug_id || '||' || q.drug_name
      and coalesce(nullif(e.value ->> 'storagePath', ''), nullif(e.value ->> 'storage_path', '')) is not null
      and exists (select 1 from public.drug_rules as r where r.drug_id = q.drug_id and r.drug_name = q.drug_name)
  );

  insert into public.drug_qr as existing (drug_id, drug_name, storage_path, original_name, updated_at)
  select
    split_part(e.key, '||', 1),
    substring(e.key from position('||' in e.key) + 2),
    coalesce(nullif(e.value ->> 'storagePath', ''), nullif(e.value ->> 'storage_path', '')),
    left(coalesce(nullif(e.value ->> 'originalName', ''), nullif(e.value ->> 'original_name', ''), nullif(e.value ->> 'filename', ''), '说明书二维码'), 160),
    case
      when coalesce(e.value ->> 'updatedAt', e.value ->> 'updated_at', '') ~ '^[0-9]{13}$'
        then to_timestamp((coalesce(e.value ->> 'updatedAt', e.value ->> 'updated_at'))::double precision / 1000.0)
      when coalesce(e.value ->> 'updatedAt', e.value ->> 'updated_at', '') ~ '^[0-9]{10}$'
        then to_timestamp((coalesce(e.value ->> 'updatedAt', e.value ->> 'updated_at'))::double precision)
      when coalesce(e.value ->> 'updatedAt', e.value ->> 'updated_at', '') = '' then now()
      else coalesce(e.value ->> 'updatedAt', e.value ->> 'updated_at')::timestamptz
    end
  from jsonb_each(v_qr) as e(key, value)
  where position('||' in e.key) > 0
    and coalesce(nullif(e.value ->> 'storagePath', ''), nullif(e.value ->> 'storage_path', '')) is not null
    and exists (
      select 1 from public.drug_rules as r
      where r.drug_id = split_part(e.key, '||', 1)
        and r.drug_name = substring(e.key from position('||' in e.key) + 2)
    )
  on conflict (drug_id, drug_name) do update set
    storage_path = excluded.storage_path,
    original_name = excluded.original_name,
    updated_at = excluded.updated_at
  where (existing.storage_path, existing.original_name, existing.updated_at)
    is distinct from (excluded.storage_path, excluded.original_name, excluded.updated_at);

  return jsonb_build_object('ok', true, 'records', v_count);
end;
$$;
revoke all on function public.replace_renal_database(jsonb) from public, anon, authenticated;
grant execute on function public.replace_renal_database(jsonb) to authenticated;

commit;

-- AFTER creating/inviting the administrator in Supabase Auth, copy that user's
-- UUID from Authentication -> Users and run this separately in SQL Editor:
-- insert into private.renal_admins (user_id)
-- values ('PASTE-AUTH-USER-UUID-HERE')
-- on conflict (user_id) do nothing;
