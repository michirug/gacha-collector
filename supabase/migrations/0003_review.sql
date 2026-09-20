-- 段階B-2: コミュニティ承認・通報 UI のための追加
-- 適用: npx supabase db query --linked --file supabase/migrations/0003_review.sql(2026-09-20 適用済み)

-- 審査中(pending)の写真を他ユーザーが見て承認できるように、pending バケットの読み取りを
-- 「本人のみ」から「サインイン済みユーザー全員」に広げる(パスは RPC 経由でしか分からない)。
-- アップロード・削除は引き続き本人のフォルダのみ。
drop policy if exists pending_select_own on storage.objects;
drop policy if exists pending_select_authenticated on storage.objects;
create policy pending_select_authenticated on storage.objects for select to authenticated
  using (bucket_id = 'photos-pending');

-- 承認候補: 指定シリーズの pending 写真のうち、自分の投稿でなく、まだ自分が承認/通報しておらず、
-- ブロックした投稿者のものでもないものを新しい順に返す
create or replace function pending_photos_for_review(p_series_id text, p_limit int default 5)
returns table (
  id uuid, item_id text, item_label text, poster_id uuid, storage_path text,
  auto_score real, approvals int, created_at timestamptz
) language sql security definer set search_path = public stable as $$
  select p.id, p.item_id, p.item_label, p.poster_id, p.storage_path, p.auto_score, p.approvals, p.created_at
  from photos p
  where p.series_id = p_series_id
    and p.status = 'pending'
    and p.poster_id <> auth.uid()
    and not exists (select 1 from approvals a where a.photo_id = p.id and a.voter_id = auth.uid())
    and not exists (select 1 from reports r where r.photo_id = p.id and r.reporter_id = auth.uid())
    and not exists (select 1 from blocks b where b.blocker_id = auth.uid() and b.blocked_id = p.poster_id)
  order by p.created_at desc
  limit greatest(1, least(p_limit, 20));
$$;
grant execute on function pending_photos_for_review(text, int) to authenticated;

-- 配信スナップショットに photo id を含める(通報・いいねの対象指定に使う)。列は末尾に追加
create or replace view approved_photo_snapshot as
select distinct on (item_id)
  item_id, series_id, maker, public_url, poster_id, likes, auto_score, approved_at, id
from photos
where status = 'approved' and public_url is not null
order by item_id, (coalesce(auto_score, 0) * 0.5 + least(likes, 50) / 100.0) desc, approved_at desc;
