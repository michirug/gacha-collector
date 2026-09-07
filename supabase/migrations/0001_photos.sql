-- ガチャ活ポケット 段階B: ユーザー写真の共有
-- 適用: Supabase ダッシュボード → SQL Editor に貼り付けて実行(または supabase db push)
--
-- 設計方針
--  * ユーザーは匿名認証(auth.users に匿名ユーザーが作られる)。個人情報は持たない
--  * 写真の本体は Storage。pending バケットは非公開、approved バケットは公開(CDN配信)
--  * 承認・通報・いいねは RPC 経由で行い、テーブルへの直接書き込みは最小限にする
--  * status: pending(自動判定待ち/承認待ち) → approved(採用) / rejected(拒否) / held(通報で保留) / removed(投稿者削除・権利者対応)

create extension if not exists "pgcrypto";

-- 投稿者(匿名ユーザー1人=1行)。ニックネームは初期は使わない(列だけ用意)
create table if not exists posters (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text,
  approved_count int not null default 0,
  report_count int not null default 0,
  blocked boolean not null default false,
  created_at timestamptz not null default now()
);

create type photo_status as enum ('pending', 'approved', 'rejected', 'held', 'removed');

create table if not exists photos (
  id uuid primary key default gen_random_uuid(),
  item_id text not null,            -- 例: kitan:fkfkowl_flocky::フクロウ
  series_id text not null,          -- 例: kitan:fkfkowl_flocky
  maker text not null,              -- 例: kitan
  poster_id uuid not null references posters (id) on delete cascade,
  status photo_status not null default 'pending',
  storage_path text not null,       -- バケット内パス。pending: {poster_id}/{id}.jpg
  public_url text,                  -- approved 後に設定
  auto_score real,                  -- 自動判定スコア 0..1(null=未判定)
  auto_detail jsonb,                -- 判定の内訳(safe_search, match, quality)
  approvals int not null default 0,
  reports int not null default 0,
  likes int not null default 0,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);
create index if not exists photos_item_status_idx on photos (item_id, status);
create index if not exists photos_poster_idx on photos (poster_id);
create index if not exists photos_status_created_idx on photos (status, created_at);

create table if not exists approvals (
  photo_id uuid not null references photos (id) on delete cascade,
  voter_id uuid not null references posters (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (photo_id, voter_id)
);

create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null references photos (id) on delete cascade,
  reporter_id uuid not null references posters (id) on delete cascade,
  reason text not null check (reason in ('wrong_item', 'inappropriate', 'copyright', 'other')),
  detail text,
  created_at timestamptz not null default now(),
  unique (photo_id, reporter_id)
);

create table if not exists likes (
  photo_id uuid not null references photos (id) on delete cascade,
  user_id uuid not null references posters (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (photo_id, user_id)
);

-- 投稿者が他ユーザーをブロック(そのユーザーの写真を自分の端末で見ない)。Play UGCポリシー要件
create table if not exists blocks (
  blocker_id uuid not null references posters (id) on delete cascade,
  blocked_id uuid not null references posters (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table posters enable row level security;
alter table photos enable row level security;
alter table approvals enable row level security;
alter table reports enable row level security;
alter table likes enable row level security;
alter table blocks enable row level security;

-- posters: 自分の行だけ読める・作れる。nickname 以外は更新不可(トリガで担保)
create policy posters_select_own on posters for select using (auth.uid() = id);
create policy posters_insert_own on posters for insert with check (auth.uid() = id);
create policy posters_update_own on posters for update using (auth.uid() = id);

-- photos: approved は全員が読める。pending/held/rejected は投稿者本人のみ
create policy photos_select on photos for select using (
  status = 'approved' or poster_id = auth.uid()
);
-- 投稿: 本人・pending 固定・ブロックされていない・レート制限(1日20枚、初回7日間は5枚)
create policy photos_insert on photos for insert with check (
  poster_id = auth.uid()
  and status = 'pending'
  and not exists (select 1 from posters p where p.id = auth.uid() and p.blocked)
  and (
    select count(*) from photos x
    where x.poster_id = auth.uid() and x.created_at > now() - interval '1 day'
  ) < case
        when (select created_at from posters where id = auth.uid()) > now() - interval '7 days' then 5
        else 20
      end
);
-- 更新は RPC(security definer)経由のみ。本人が自分の投稿を removed にするのは許可
create policy photos_update_own_remove on photos for update
  using (poster_id = auth.uid())
  with check (poster_id = auth.uid() and status = 'removed');

create policy approvals_insert on approvals for insert with check (voter_id = auth.uid());
create policy approvals_select_own on approvals for select using (voter_id = auth.uid());
create policy reports_insert on reports for insert with check (reporter_id = auth.uid());
create policy reports_select_own on reports for select using (reporter_id = auth.uid());
create policy likes_insert on likes for insert with check (user_id = auth.uid());
create policy likes_delete on likes for delete using (user_id = auth.uid());
create policy likes_select_own on likes for select using (user_id = auth.uid());
create policy blocks_all_own on blocks for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 集計トリガ・RPC
-- ---------------------------------------------------------------------------

-- 承認: 3件で approved。自分の投稿には承認できない
create or replace function approve_photo(p_photo_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_poster uuid;
  v_count int;
  v_needed int := 3;
begin
  select poster_id into v_poster from photos where id = p_photo_id and status = 'pending';
  if v_poster is null then return; end if;
  if v_poster = auth.uid() then raise exception 'cannot approve own photo'; end if;
  insert into approvals (photo_id, voter_id) values (p_photo_id, auth.uid()) on conflict do nothing;
  select count(*) into v_count from approvals where photo_id = p_photo_id;
  -- 通報履歴のある投稿者は必要承認数を増やす
  if (select report_count from posters where id = v_poster) >= 3 then v_needed := 5; end if;
  update photos set approvals = v_count where id = p_photo_id;
  if v_count >= v_needed and coalesce((select auto_score from photos where id = p_photo_id), 0) >= 0.5 then
    update photos set status = 'approved', approved_at = now() where id = p_photo_id;
    update posters set approved_count = approved_count + 1 where id = v_poster;
  end if;
end $$;

-- 通報: 3件で held。投稿者の report_count を加算
create or replace function report_photo(p_photo_id uuid, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_poster uuid;
  v_count int;
begin
  select poster_id into v_poster from photos where id = p_photo_id and status in ('pending', 'approved');
  if v_poster is null then return; end if;
  insert into reports (photo_id, reporter_id, reason, detail) values (p_photo_id, auth.uid(), p_reason, p_detail)
    on conflict do nothing;
  select count(*) into v_count from reports where photo_id = p_photo_id;
  update photos set reports = v_count where id = p_photo_id;
  if v_count >= 3 then
    update photos set status = 'held' where id = p_photo_id;
    update posters set report_count = report_count + 1 where id = v_poster;
  end if;
end $$;

-- いいね(トグル)
create or replace function toggle_like(p_photo_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_liked boolean;
begin
  if exists (select 1 from likes where photo_id = p_photo_id and user_id = auth.uid()) then
    delete from likes where photo_id = p_photo_id and user_id = auth.uid();
    v_liked := false;
  else
    insert into likes (photo_id, user_id) values (p_photo_id, auth.uid());
    v_liked := true;
  end if;
  update photos set likes = (select count(*) from likes where photo_id = p_photo_id) where id = p_photo_id;
  return v_liked;
end $$;

-- 投稿者本人による取り消し(status=removed、Storage 側の削除は Edge Function が行う)
create or replace function remove_own_photo(p_photo_id uuid)
returns void language sql security definer set search_path = public as $$
  update photos set status = 'removed' where id = p_photo_id and poster_id = auth.uid();
$$;

-- 配信スナップショット用: アイテムごとの採用写真(最良1枚)
create or replace view approved_photo_snapshot as
select distinct on (item_id)
  item_id, series_id, maker, public_url, poster_id, likes, auto_score, approved_at
from photos
where status = 'approved' and public_url is not null
order by item_id, (coalesce(auto_score, 0) * 0.5 + least(likes, 50) / 100.0) desc, approved_at desc;

grant execute on function approve_photo(uuid) to authenticated;
grant execute on function report_photo(uuid, text, text) to authenticated;
grant execute on function toggle_like(uuid) to authenticated;
grant execute on function remove_own_photo(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage バケットとポリシー
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('photos-pending', 'photos-pending', false, 2097152, array['image/jpeg'])
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('photos-approved', 'photos-approved', true, 2097152, array['image/jpeg'])
  on conflict (id) do nothing;

-- pending: 自分のフォルダ({uid}/...)にだけアップロード・読み取り・削除できる
create policy pending_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'photos-pending' and (storage.foldername(name))[1] = auth.uid()::text);
create policy pending_select_own on storage.objects for select to authenticated
  using (bucket_id = 'photos-pending' and (storage.foldername(name))[1] = auth.uid()::text);
create policy pending_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'photos-pending' and (storage.foldername(name))[1] = auth.uid()::text);
-- approved: 読み取りは公開バケットなので誰でも可。書き込みは service_role(Edge Function)のみ
create policy approved_select_all on storage.objects for select using (bucket_id = 'photos-approved');
