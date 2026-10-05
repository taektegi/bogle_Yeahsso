-- 이미지 파일을 `assets` 테이블 한 곳에서 관리한다 (담당 A).
--
-- 왜 필요한가
--   - 업로드한 원본은 생성 작업이 쓰기 전에 `sourceAssetId`로 가리킬 수 있어야 한다 (FR-03.3).
--   - 소유권·크기·해상도를 한곳에 기록하고, 앱에는 안정적인 assetId + 만료되는 서명 URL로 준다.
--   - 친구 삭제·미사용 파일 정리·계정 삭제 때 "assets를 조회 → Storage 파일 삭제 → 행 삭제"로 처리한다.
--
-- 이 마이그레이션은 friends의 경로 컬럼(source_path/art_path/thumbnail_path)을
-- assets 참조 컬럼으로 바꾼다. 아직 원격에 적용된 적이 없고 데이터가 없는 단계라서
-- 기존 행을 옮기지 않는다 (행이 있으면 아래에서 실패한다).

do $$
begin
  if exists (select 1 from public.friends) then
    raise exception
      'public.friends has rows. This migration replaces the path columns and does not backfill them. '
      'On a local dev database run `supabase db reset`.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- assets: 업로드 원본, 생성된 캐릭터 아트·썸네일, 모션 GIF
-- ---------------------------------------------------------------------------

create table public.assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  -- source: 업로드 원본(그림판 PNG·사진 JPEG), art: 생성된 투명 캐릭터 PNG,
  -- thumbnail: 썸네일, motion: 모션 클립 GIF (담당 C가 쓴다)
  kind text not null,
  -- 비공개 bucket(bogle-media) 안의 객체 경로. 항상 '{user_id}/'로 시작한다 (FR-03.4).
  storage_path text not null,
  content_type text not null,
  byte_size bigint not null,
  width integer not null,
  height integer not null,

  created_at timestamptz not null default now(),

  -- friends가 "내 에셋"만 가리키도록 하는 복합 외래 키용
  constraint assets_user_id_id_key unique (user_id, id),
  constraint assets_storage_path_key unique (storage_path),
  constraint assets_kind_check
    check (kind in ('source', 'art', 'thumbnail', 'motion')),
  constraint assets_content_type_check
    check (content_type in ('image/png', 'image/jpeg', 'image/gif')),
  constraint assets_byte_size_check check (byte_size > 0),
  constraint assets_dimensions_check check (width > 0 and height > 0),
  constraint assets_storage_path_owner_check
    check (starts_with(storage_path, user_id::text || '/'))
);

-- 미사용 업로드·작업 결과를 일정 시간 뒤 정리할 때 오래된 순으로 찾는다 (FR-04.8).
create index assets_created_at_idx on public.assets (created_at);

-- ---------------------------------------------------------------------------
-- friends: 경로 컬럼 → assets 참조
-- ---------------------------------------------------------------------------

alter table public.friends
  drop column source_path,
  drop column art_path,
  drop column thumbnail_path;

alter table public.friends
  add column source_asset_id uuid,
  add column art_asset_id uuid not null,
  add column thumbnail_asset_id uuid not null;

-- 에셋 하나는 친구 한 명에게만 속한다. 친구를 지워도 다른 친구의 파일이 사라지지 않게 한다.
alter table public.friends
  add constraint friends_source_asset_id_key unique (source_asset_id),
  add constraint friends_art_asset_id_key unique (art_asset_id),
  add constraint friends_thumbnail_asset_id_key unique (thumbnail_asset_id);

-- (user_id, asset_id)가 assets(user_id, id)와 일치해야 하므로 남의 에셋은 참조할 수 없다.
-- on delete 동작은 기본(no action)이다: 친구가 참조 중인 에셋은 먼저 지울 수 없고,
-- 친구를 지운 뒤 에셋을 지운다. 사용자 삭제는 두 테이블을 함께 연쇄 삭제하므로 문제없다.
-- 에셋의 kind(source/art/thumbnail)가 맞는지는 DB가 아니라 API가 검사한다.
alter table public.friends
  add constraint friends_source_asset_fkey
    foreign key (user_id, source_asset_id) references public.assets (user_id, id),
  add constraint friends_art_asset_fkey
    foreign key (user_id, art_asset_id) references public.assets (user_id, id),
  add constraint friends_thumbnail_asset_fkey
    foreign key (user_id, thumbnail_asset_id) references public.assets (user_id, id);

-- ---------------------------------------------------------------------------
-- RLS와 권한 (FR-01.4): 앱은 내 것만 읽고, 쓰기는 서버(service_role)만 한다.
-- ---------------------------------------------------------------------------

alter table public.assets enable row level security;

revoke all on public.assets from anon, authenticated;
grant select on public.assets to authenticated;

create policy assets_select_own
  on public.assets for select to authenticated
  using ((select auth.uid()) = user_id);
