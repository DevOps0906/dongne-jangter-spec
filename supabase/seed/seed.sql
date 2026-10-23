-- 개발용 기준 데이터 (개인정보 없음)
-- 0001_init.sql 적용 후 실행합니다.

insert into public.categories (id, name, sort_order) values
  (1, '디지털·가전', 1),
  (2, '가구·인테리어', 2),
  (3, '생활·주방', 3),
  (4, '유아동', 4),
  (5, '의류·잡화', 5),
  (6, '스포츠·레저', 6),
  (7, '도서·취미', 7),
  (8, '기타', 99)
on conflict (id) do nothing;

insert into public.regions (sido, sigungu, dong, center_lat, center_lng) values
  ('서울특별시', '마포구', '망원동', 37.5563, 126.9020),
  ('서울특별시', '마포구', '합정동', 37.5496, 126.9139),
  ('서울특별시', '마포구', '서교동', 37.5548, 126.9220)
on conflict (sido, sigungu, dong) do nothing;
