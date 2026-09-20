-- 段階B-2: 自動判定(Edge Function judge-photo)のための追加
-- 適用: Supabase ダッシュボード → SQL Editor に貼り付けて実行(0001 の後)

-- 一致度判定に使う表示名「シリーズ名 / アイテム名」。アプリが投稿時に入れる(旧クライアントは null)
alter table photos add column if not exists item_label text;

-- 承認: 3件(通報履歴のある投稿者は5件)で approved。
-- 0001 では auto_score >= 0.5 も条件にしていたが、Edge Function 未判定(null)や低スコアでも
-- コミュニティ承認で救済できる設計にするため、条件を status = 'pending' のみにする。
-- 明確な違反(SafeSearch)は Edge Function が rejected にするので、ここには来ない。
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
  if (select report_count from posters where id = v_poster) >= 3 then v_needed := 5; end if;
  update photos set approvals = v_count where id = p_photo_id;
  if v_count >= v_needed then
    update photos set status = 'approved', approved_at = now() where id = p_photo_id;
    update posters set approved_count = approved_count + 1 where id = v_poster;
  end if;
end $$;
