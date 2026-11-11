-- Storage buckets and SECURE access policies for the CureNurture apps.
--
-- Recreates the three buckets the original project used, with tighter rules
-- than the original anonymous / public ones. Paths follow the apps' code:
--   medical_docs      <patients.id>/<file>      (Admin Panel: list + signed URL;
--                                                 mobile: upload to own folder)
--                     <profiles.id>/<file>      (a few older records)
--   patient_profiles  patients/<auth uid>_<ms>.jpg
--   donation_receipts legacy proof-of-payment images (read-only history)
--
-- Access (authenticated users only; nothing for anon):
--   medical_docs      read:   the patient who owns the folder, the ACTIVE admin
--                             of that patient's centre, superadmins
--                     write:  the owning patient, own folder only (no deletes)
--   patient_profiles  read:   the owner, the active admin of the owner's centre,
--                             superadmins
--                     write:  the owner only
--   donation_receipts read:   superadmins only; no writes
--
-- "Active admin of the centre" reuses public.curenurture_admin_clinic_id()
-- (v4: role admin + status active + is_active) and "superadmin" reuses
-- public.curenurture_is_superadmin(). Buckets are private: files are opened
-- with signed URLs, never public links. No ownership or role is elevated.

insert into storage.buckets (id, name, public)
values ('medical_docs', 'medical_docs', false),
       ('patient_profiles', 'patient_profiles', false),
       ('donation_receipts', 'donation_receipts', false)
on conflict (id) do update set public = false;

-- Helpers (SECURITY DEFINER so the checks do not depend on the RLS of the
-- tables they read; they return only true/false).
create or replace function public.storage_medical_doc_readable(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.curenurture_is_superadmin(), false)
      or p_folder = auth.uid()::text
      or exists (
        select 1 from public.patients pt
        where pt.id::text = p_folder
          and (pt.profile_id = auth.uid()
               or pt.clinic_id = public.curenurture_admin_clinic_id())
      )
      or exists (
        select 1 from public.profiles pr
        where pr.id::text = p_folder
          and pr.clinic_id is not null
          and pr.clinic_id = public.curenurture_admin_clinic_id()
      );
$$;

create or replace function public.storage_medical_doc_writable(p_folder text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and (p_folder = auth.uid()::text
          or exists (
            select 1 from public.patients pt
            where pt.id::text = p_folder and pt.profile_id = auth.uid()
          ));
$$;

create or replace function public.storage_profile_image_readable(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.curenurture_is_superadmin(), false)
      or (auth.uid() is not null and p_name like 'patients/' || auth.uid()::text || '\_%')
      or exists (
        select 1 from public.patients pt
        where pt.profile_id::text = split_part(split_part(p_name, '/', 2), '_', 1)
          and pt.clinic_id = public.curenurture_admin_clinic_id()
      );
$$;

revoke all on function public.storage_medical_doc_readable(text) from public, anon;
revoke all on function public.storage_medical_doc_writable(text) from public, anon;
revoke all on function public.storage_profile_image_readable(text) from public, anon;
grant execute on function public.storage_medical_doc_readable(text) to authenticated;
grant execute on function public.storage_medical_doc_writable(text) to authenticated;
grant execute on function public.storage_profile_image_readable(text) to authenticated;

-- medical_docs
drop policy if exists "medical_docs: read own, own-centre or superadmin" on storage.objects;
create policy "medical_docs: read own, own-centre or superadmin"
  on storage.objects for select to authenticated
  using (bucket_id = 'medical_docs'
         and public.storage_medical_doc_readable((storage.foldername(name))[1]));

drop policy if exists "medical_docs: patient uploads to own folder" on storage.objects;
create policy "medical_docs: patient uploads to own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'medical_docs'
              and public.storage_medical_doc_writable((storage.foldername(name))[1]));

drop policy if exists "medical_docs: patient updates own folder" on storage.objects;
create policy "medical_docs: patient updates own folder"
  on storage.objects for update to authenticated
  using (bucket_id = 'medical_docs'
         and public.storage_medical_doc_writable((storage.foldername(name))[1]))
  with check (bucket_id = 'medical_docs'
              and public.storage_medical_doc_writable((storage.foldername(name))[1]));

-- patient_profiles
drop policy if exists "patient_profiles: read own, own-centre or superadmin" on storage.objects;
create policy "patient_profiles: read own, own-centre or superadmin"
  on storage.objects for select to authenticated
  using (bucket_id = 'patient_profiles' and public.storage_profile_image_readable(name));

drop policy if exists "patient_profiles: owner uploads" on storage.objects;
create policy "patient_profiles: owner uploads"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'patient_profiles'
              and name like 'patients/' || auth.uid()::text || '\_%');

drop policy if exists "patient_profiles: owner updates" on storage.objects;
create policy "patient_profiles: owner updates"
  on storage.objects for update to authenticated
  using (bucket_id = 'patient_profiles' and name like 'patients/' || auth.uid()::text || '\_%')
  with check (bucket_id = 'patient_profiles' and name like 'patients/' || auth.uid()::text || '\_%');

-- donation_receipts (legacy, read-only history)
drop policy if exists "donation_receipts: superadmin read" on storage.objects;
create policy "donation_receipts: superadmin read"
  on storage.objects for select to authenticated
  using (bucket_id = 'donation_receipts' and public.curenurture_is_superadmin());

do $$
begin
  if (select count(*) from storage.buckets where id in ('medical_docs', 'patient_profiles', 'donation_receipts') and not public) <> 3 then
    raise exception 'POST-CHECK FAILED: the three buckets must exist and be private';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
             and (roles && array['anon', 'public']::name[]) and policyname like any (array['medical_docs:%', 'patient_profiles:%', 'donation_receipts:%'])) then
    raise exception 'POST-CHECK FAILED: a CureNurture storage policy is open to anon';
  end if;
end $$;
