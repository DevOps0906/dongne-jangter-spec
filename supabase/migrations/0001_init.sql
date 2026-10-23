-- 동네장터 초기 스키마 (초안)
-- 상태: 검토용 초안. 아직 Supabase 프로젝트에 적용하지 않았습니다.
-- 적용 전에 개발용 프로젝트에서 먼저 실행하고 RLS 정책을 테스트하세요.

-- ─────────────────────────────────────────────
-- 0. 확장 및 공통
-- ─────────────────────────────────────────────
create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ─────────────────────────────────────────────
-- 1. 사용자 프로필 (auth.users 1:1)
-- ─────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null unique check (char_length(nickname) between 2 and 12),
  avatar_url text,
  manner_temp numeric(4, 1) not null default 36.5 check (manner_temp between 0 and 99.9),
  review_positive_count int not null default 0,
  review_total_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────
-- 2. 동네(법정동) 과 사용자 동네 인증
-- ─────────────────────────────────────────────
create table if not exists public.regions (
  id uuid primary key default gen_random_uuid(),
  sido text not null,
  sigungu text not null,
  dong text not null,            -- 법정동명
  center_lat double precision,
  center_lng double precision,
  unique (sido, sigungu, dong)
);

create table if not exists public.user_regions (
  user_id uuid not null references public.profiles (id) on delete cascade,
  region_id uuid not null references public.regions (id),
  is_primary boolean not null default false,
  verified_at timestamptz not null default now(),
  primary key (user_id, region_id)
);

-- 사용자당 대표 동네는 하나만
create unique index if not exists user_regions_one_primary
  on public.user_regions (user_id) where is_primary;

-- ─────────────────────────────────────────────
-- 3. 상품
-- ─────────────────────────────────────────────
create table if not exists public.categories (
  id smallint primary key,
  name text not null unique,
  sort_order smallint not null default 0
);

create type public.product_status as enum ('selling', 'reserved', 'sold');

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  region_id uuid not null references public.regions (id),
  category_id smallint references public.categories (id),
  title text not null check (char_length(title) between 1 and 100),
  description text not null default '',
  price integer not null check (price >= 0),
  status public.product_status not null default 'selling',
  view_count int not null default 0,
  favorite_count int not null default 0,
  chat_count int not null default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists products_region_status_idx
  on public.products (region_id, status, created_at desc);

create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  storage_path text not null,    -- Supabase Storage 경로
  sort_order smallint not null default 0
);

create table if not exists public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

-- ─────────────────────────────────────────────
-- 4. 채팅과 가격 제안
-- ─────────────────────────────────────────────
create table if not exists public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  unique (product_id, buyer_id),
  check (buyer_id <> seller_id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_room_idx
  on public.chat_messages (room_id, created_at);

create type public.offer_status as enum ('pending', 'accepted', 'rejected');

create table if not exists public.price_offers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  price integer not null check (price >= 0),
  status public.offer_status not null default 'pending',
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- 5. 거래 후기와 매너온도
-- ─────────────────────────────────────────────
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  reviewer_id uuid not null references public.profiles (id) on delete cascade,
  reviewee_id uuid not null references public.profiles (id) on delete cascade,
  is_positive boolean not null,
  keywords text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (product_id, reviewer_id),
  check (reviewer_id <> reviewee_id)
);

-- 후기 한 건마다 매너온도 반영 (증감 값은 정책 값이므로 조정 가능)
create or replace function public.apply_review_to_manner_temp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  delta numeric(4, 1);
begin
  delta := case when new.is_positive then 0.5 else -0.5 end;

  update public.profiles
     set manner_temp = least(99.9, greatest(0, manner_temp + delta)),
         review_total_count = review_total_count + 1,
         review_positive_count = review_positive_count + case when new.is_positive then 1 else 0 end
   where id = new.reviewee_id;

  return new;
end;
$$;

create trigger reviews_apply_manner_temp
after insert on public.reviews
for each row execute function public.apply_review_to_manner_temp();

-- ─────────────────────────────────────────────
-- 6. 동네생활 커뮤니티
-- ─────────────────────────────────────────────
create type public.post_category as enum ('question', 'info', 'free', 'local_news');

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  region_id uuid not null references public.regions (id),
  category public.post_category not null default 'free',
  title text not null check (char_length(title) between 1 and 100),
  body text not null default '',
  image_paths text[] not null default '{}',
  like_count int not null default 0,
  comment_count int not null default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists posts_region_idx
  on public.posts (region_id, created_at desc);

create trigger posts_set_updated_at
before update on public.posts
for each row execute function public.set_updated_at();

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- 7. 신고와 차단
-- ─────────────────────────────────────────────
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('product', 'post', 'comment', 'user')),
  target_id uuid not null,
  reason text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- ─────────────────────────────────────────────
-- 8. 보안 정책 (RLS)
-- ─────────────────────────────────────────────
alter table public.profiles enable row level security;
alter table public.regions enable row level security;
alter table public.user_regions enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.favorites enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.chat_messages enable row level security;
alter table public.price_offers enable row level security;
alter table public.reviews enable row level security;
alter table public.posts enable row level security;
alter table public.post_comments enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;

-- 채팅방 참여자 여부 확인 (정책 내 재귀 방지용 함수)
create or replace function public.is_chat_participant(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.chat_rooms r
    where r.id = p_room_id
      and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
  );
$$;

-- profiles: 누구나 읽기, 본인만 수정
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using (true);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- regions, categories: 누구나 읽기 (쓰기는 관리자 전용으로 정책 없음)
drop policy if exists regions_read on public.regions;
create policy regions_read on public.regions for select using (true);
drop policy if exists categories_read on public.categories;
create policy categories_read on public.categories for select using (true);

-- user_regions: 본인 것만
drop policy if exists user_regions_own on public.user_regions;
create policy user_regions_own on public.user_regions for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- products: 삭제되지 않은 상품은 누구나 읽기, 작성·수정·삭제는 판매자만
drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (deleted_at is null);
drop policy if exists products_insert_own on public.products;
create policy products_insert_own on public.products for insert
  with check (seller_id = auth.uid());
drop policy if exists products_update_own on public.products;
create policy products_update_own on public.products for update
  using (seller_id = auth.uid()) with check (seller_id = auth.uid());

-- product_images: 상품 판매자만 관리
drop policy if exists product_images_read on public.product_images;
create policy product_images_read on public.product_images for select using (true);
drop policy if exists product_images_manage_own on public.product_images;
create policy product_images_manage_own on public.product_images for all
  using (exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid()))
  with check (exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid()));

-- favorites: 본인 것만
drop policy if exists favorites_own on public.favorites;
create policy favorites_own on public.favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- chat_rooms: 구매자와 판매자만 읽고 생성 (생성자는 구매자)
drop policy if exists chat_rooms_participant_read on public.chat_rooms;
create policy chat_rooms_participant_read on public.chat_rooms for select
  using (buyer_id = auth.uid() or seller_id = auth.uid());
drop policy if exists chat_rooms_buyer_insert on public.chat_rooms;
create policy chat_rooms_buyer_insert on public.chat_rooms for insert
  with check (buyer_id = auth.uid());

-- chat_messages: 참여자만 읽고, 본인 이름으로만 쓰기
drop policy if exists chat_messages_participant_read on public.chat_messages;
create policy chat_messages_participant_read on public.chat_messages for select
  using (public.is_chat_participant(room_id));
drop policy if exists chat_messages_participant_insert on public.chat_messages;
create policy chat_messages_participant_insert on public.chat_messages for insert
  with check (sender_id = auth.uid() and public.is_chat_participant(room_id));

-- price_offers: 제안한 구매자와 해당 상품 판매자가 읽기, 구매자만 생성
drop policy if exists price_offers_read on public.price_offers;
create policy price_offers_read on public.price_offers for select
  using (
    buyer_id = auth.uid()
    or exists (select 1 from public.products p where p.id = product_id and p.seller_id = auth.uid())
  );
drop policy if exists price_offers_buyer_insert on public.price_offers;
create policy price_offers_buyer_insert on public.price_offers for insert
  with check (buyer_id = auth.uid());

-- reviews: 누구나 읽기, 거래 당사자 중 리뷰어 본인만 작성
drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews for select using (true);
drop policy if exists reviews_insert_own on public.reviews;
create policy reviews_insert_own on public.reviews for insert
  with check (reviewer_id = auth.uid());

-- posts, post_comments: 누구나 읽기, 작성자만 쓰기·수정·삭제
drop policy if exists posts_read on public.posts;
create policy posts_read on public.posts for select using (deleted_at is null);
drop policy if exists posts_insert_own on public.posts;
create policy posts_insert_own on public.posts for insert
  with check (author_id = auth.uid());
drop policy if exists posts_update_own on public.posts;
create policy posts_update_own on public.posts for update
  using (author_id = auth.uid()) with check (author_id = auth.uid());

drop policy if exists post_comments_read on public.post_comments;
create policy post_comments_read on public.post_comments for select using (true);
drop policy if exists post_comments_insert_own on public.post_comments;
create policy post_comments_insert_own on public.post_comments for insert
  with check (author_id = auth.uid());
drop policy if exists post_comments_delete_own on public.post_comments;
create policy post_comments_delete_own on public.post_comments for delete
  using (author_id = auth.uid());

-- reports, blocks: 본인 기록만
drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports for insert
  with check (reporter_id = auth.uid());
drop policy if exists reports_read_own on public.reports;
create policy reports_read_own on public.reports for select
  using (reporter_id = auth.uid());

drop policy if exists blocks_own on public.blocks;
create policy blocks_own on public.blocks for all
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());
