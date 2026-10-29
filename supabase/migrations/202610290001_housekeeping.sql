alter table public.properties add column if not exists region text;
alter table public.profiles add column if not exists region text;

create table if not exists public.cleaning_tasks (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  region text,
  assigned_to uuid references public.profiles(id) on delete set null,
  checked_out_at timestamptz not null default now(),
  deadline_at timestamptz not null,
  status text not null default 'assigned' check (status in ('assigned','cleaning','completed')),
  photos text[] not null default '{}',
  completed_at timestamptz,
  was_late boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists cleaning_tasks_assigned_deadline_idx on public.cleaning_tasks (assigned_to, deadline_at);
alter table public.cleaning_tasks enable row level security;
grant select on public.cleaning_tasks to authenticated;

drop policy if exists cleaning_tasks_read_assigned_or_admin on public.cleaning_tasks;
create policy cleaning_tasks_read_assigned_or_admin on public.cleaning_tasks
  for select to authenticated using (
    assigned_to = auth.uid() or exists (
      select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'
    )
  );

create or replace function public.assign_cleaning_task_for_checkout()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_region text;
  v_cleaner uuid;
begin
  if new.status = 'checked_out' and old.status is distinct from 'checked_out' then
    select p.region into v_region from public.properties p where p.id = new.property_id;
    select pr.id into v_cleaner
    from public.profiles pr
    left join public.cleaning_tasks ct on ct.assigned_to = pr.id and ct.status <> 'completed'
    where pr.role = 'housekeeping'
      and v_region is not null
      and lower(trim(pr.region)) = lower(trim(v_region))
    group by pr.id
    order by count(ct.id), pr.id
    limit 1;

    insert into public.cleaning_tasks (booking_id, property_id, region, assigned_to, checked_out_at, deadline_at)
    values (new.id, new.property_id, v_region, v_cleaner, clock_timestamp(), clock_timestamp() + interval '5 hours')
    on conflict (booking_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists booking_checkout_creates_cleaning_task on public.bookings;
create trigger booking_checkout_creates_cleaning_task
after update of status on public.bookings
for each row execute function public.assign_cleaning_task_for_checkout();

create or replace function public.assign_cleaning_task(p_task_id uuid, p_cleaner_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_region text;
  v_cleaner_region text;
  v_role text;
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin') then
    raise exception 'Only admins can assign cleaning tasks';
  end if;
  select region into v_region from public.cleaning_tasks where id = p_task_id for update;
  if not found then raise exception 'Cleaning task not found'; end if;
  select role, region into v_role, v_cleaner_region from public.profiles where id = p_cleaner_id;
  if v_role <> 'housekeeping' or v_region is null or lower(trim(v_region)) <> lower(trim(coalesce(v_cleaner_region, ''))) then
    raise exception 'Cleaner region must match the property region';
  end if;
  update public.cleaning_tasks set assigned_to = p_cleaner_id where id = p_task_id;
end;
$$;
revoke all on function public.assign_cleaning_task(uuid, uuid) from public;
grant execute on function public.assign_cleaning_task(uuid, uuid) to authenticated;
create or replace function public.complete_cleaning_task(p_task_id uuid, p_photos text[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_assigned uuid;
begin
  select assigned_to into v_assigned from public.cleaning_tasks where id = p_task_id for update;
  if not found then raise exception 'Cleaning task not found'; end if;
  if v_assigned is distinct from auth.uid() and not exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'
  ) then raise exception 'You are not assigned to this cleaning task'; end if;
  if coalesce(array_length(p_photos, 1), 0) < 1 then raise exception 'Upload at least one room photo'; end if;
  update public.cleaning_tasks
  set status = 'completed', photos = p_photos, completed_at = clock_timestamp(), was_late = clock_timestamp() > deadline_at
  where id = p_task_id;
end;
$$;
revoke all on function public.complete_cleaning_task(uuid, text[]) from public;
grant execute on function public.complete_cleaning_task(uuid, text[]) to authenticated;

insert into storage.buckets (id, name, public)
values ('cleaning-photos', 'cleaning-photos', false)
on conflict (id) do nothing;

drop policy if exists cleaning_photos_read_assigned on storage.objects;
create policy cleaning_photos_read_assigned on storage.objects
  for select to authenticated using (
    bucket_id = 'cleaning-photos' and exists (
      select 1 from public.cleaning_tasks t
      where t.id::text = split_part(name, '/', 1)
        and (t.assigned_to = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
    )
  );
drop policy if exists cleaning_photos_upload_assigned on storage.objects;
create policy cleaning_photos_upload_assigned on storage.objects
  for insert to authenticated with check (
    bucket_id = 'cleaning-photos' and exists (
      select 1 from public.cleaning_tasks t
      where t.id::text = split_part(name, '/', 1) and t.assigned_to = auth.uid()
    )
  );
