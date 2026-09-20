-- 段階B-3: いいね・差し替え(1アイテム最大5枚保持)
-- 適用: npx supabase db query --linked --file supabase/migrations/0004_likes_cap.sql(2026-09-20 適用済み)

-- 承認: 3件(通報履歴のある投稿者は5件)で approved。採用後、同じアイテムの採用写真が5枚を超えたら
-- 評価(auto_score×0.5 + min(likes,50)/100)が最も低いものを removed にする(Storage の削除は Edge Function)。
-- 配信スナップショットは approved_photo_snapshot ビューが常に最良1枚を選ぶので、差し替えは自動で起きる。
create or replace function approve_photo(p_photo_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_poster uuid;
  v_item text;
  v_count int;
  v_needed int := 3;
begin
  select poster_id, item_id into v_poster, v_item from photos where id = p_photo_id and status = 'pending';
  if v_poster is null then return; end if;
  if v_poster = auth.uid() then raise exception 'cannot approve own photo'; end if;
  insert into approvals (photo_id, voter_id) values (p_photo_id, auth.uid()) on conflict do nothing;
  select count(*) into v_count from approvals where photo_id = p_photo_id;
  if (select report_count from posters where id = v_poster) >= 3 then v_needed := 5; end if;
  update photos set approvals = v_count where id = p_photo_id;
  if v_count >= v_needed then
    update photos set status = 'approved', approved_at = now() where id = p_photo_id;
    update posters set approved_count = approved_count + 1 where id = v_poster;
    update photos set status = 'removed'
    where id in (
      select id from photos where item_id = v_item and status = 'approved'
      order by (coalesce(auto_score, 0) * 0.5 + least(likes, 50) / 100.0) desc, approved_at desc
      offset 5
    );
  end if;
end $$;

-- 自分の貢献(実績用): 採用中の写真数と、シリーズごとの採用アイテム数
create or replace function my_contribution()
returns table (series_id text, approved_items int)
language sql security definer set search_path = public stable as $$
  select series_id, count(distinct item_id)::int
  from photos
  where poster_id = auth.uid() and status = 'approved'
  group by series_id;
$$;
grant execute on function my_contribution() to authenticated;
