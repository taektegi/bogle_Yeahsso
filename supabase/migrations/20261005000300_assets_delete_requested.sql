-- 삭제를 요청한 에셋 표시 (담당 A).
--
-- 친구를 삭제하면 그 친구의 에셋은 `delete_requested_at`이 채워진다. 이 표시가 있고 아무 친구도
-- 참조하지 않는 에셋은 Storage 파일 삭제가 실패했더라도 정리 작업이 **나이와 상관없이** 바로 다시
-- 지운다. 표시가 없는 에셋(업로드만 하고 쓰지 않은 것 등)은 24시간이 지난 뒤에 정리한다 (FR-04.8).

alter table public.assets
  add column delete_requested_at timestamptz;

-- 정리 작업이 "표시된 것"만 빠르게 찾도록 한다.
create index assets_delete_requested_at_idx
  on public.assets (delete_requested_at)
  where delete_requested_at is not null;
