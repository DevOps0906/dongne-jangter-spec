# dongne-jangter-spec

동네장터의 **공용 기준 레포**입니다. 기획, 디자인, 디자인 토큰, 데이터베이스 스키마가 여기에 있습니다. 구현 코드는 없고, 웹과 Flutter 구현 레포가 이 레포를 서브모듈로 가져다 씁니다.

## 3개 레포의 관계

| 레포 | 역할 | 이 레포와의 관계 |
|---|---|---|
| **dongne-jangter-spec** (이 레포) | 기획·디자인·토큰·스키마의 단일 원본 | — |
| [dongne-jangter-web](https://github.com/DevOps0906/dongne-jangter-web) | Next.js 웹/PWA 구현 | `spec/` 서브모듈로 참조 |
| [dongne-jangter-flutter](https://github.com/DevOps0906/dongne-jangter-flutter) | Flutter 앱 구현 | `spec/` 서브모듈로 참조 |

- 디자인은 한 벌입니다. 웹과 Flutter가 같은 캔버스와 같은 토큰을 씁니다.
- 데이터베이스도 한 벌입니다. Supabase 프로젝트는 하나이고, 스키마는 이 레포의 `supabase/`에서 관리합니다.
- 값을 바꿀 때는 이 레포를 먼저 고치고, 구현 레포에서 서브모듈을 갱신합니다.

## 폴더 구조

```
dongne-jangter-spec/
├── docs/
│   ├── planning/
│   │   ├── master-plan.md          종합 기획안 (Markdown)
│   │   └── master-plan.pdf         종합 기획안 (PDF)
│   └── design/
│       ├── pattern-mapping.md      디자인 패턴(A~O)과 21개 화면 매핑
│       └── structure-diagram.html  21개 화면 구조도 (브라우저에서 열기)
├── design/
│   └── canvas/                     디자인 캔버스 (canvas.json + 보드 22개)
├── tokens/
│   └── tokens.json                 색·간격·radius·글자 크기(반응형 3구간) 단일 원본
└── supabase/
    ├── migrations/
    │   └── 0001_init.sql           테이블, 인덱스, 트리거, RLS 정책
    └── seed/
        └── seed.sql                카테고리와 시범 동네 데이터 (개인정보 없음)
```

## 사용 방법

### 1. 구현 레포에서 서브모듈로 연결하기

```bash
# 웹 또는 Flutter 레포 루트에서
git submodule add https://github.com/DevOps0906/dongne-jangter-spec.git spec
git submodule update --init --recursive

# 다른 기기에서 클론할 때
git clone --recurse-submodules <구현 레포 주소>
```

### 2. 토큰 바꾸기

1. `tokens/tokens.json`을 수정합니다.
2. 이 레포에 커밋하고 push합니다.
3. 구현 레포에서 `git submodule update --remote spec`을 실행합니다.
4. 구현 레포의 생성 스크립트를 실행해 `tokens.css`(웹)와 `tokens.g.dart`(Flutter)를 다시 만듭니다.

생성된 파일은 직접 고치지 않습니다. 값은 항상 `tokens.json`에서만 바꿉니다.

### 3. 데이터베이스 적용하기

1. 개발용 Supabase 프로젝트에 `supabase/migrations/0001_init.sql`을 실행합니다.
2. `supabase/seed/seed.sql`을 실행해 카테고리와 동네 데이터를 넣습니다.
3. RLS 정책은 적용 후 사용자 두 명 이상으로 직접 테스트합니다.

새 마이그레이션은 `0002_...sql`처럼 번호를 올려서 추가합니다. 적용된 파일은 수정하지 않습니다.

## 현재 상태

| 항목 | 상태 |
|---|---|
| 기획안, 패턴 매핑, 구조도 | 완료 |
| 디자인 캔버스 (22개 보드) | 완료. 시각 점검 전 |
| `tokens.json` | 초안 (v0.1.0) |
| `supabase/migrations/0001_init.sql` | 초안. 실제 프로젝트에 적용 전 |
| `supabase/seed/seed.sql` | 초안 |

## 알려진 사항

- 라이트 테마만 있습니다. 다크 테마는 아직 없습니다.
- 캔버스의 `.dc.html` 파일은 `./support.js`를 참조합니다. 이 파일은 Artifact 런타임이 제공하므로 레포에 없습니다.
- 기획안과 패턴 매핑 문서에는 참고한 레퍼런스 앱 기준 표기(`com.nomad.karrot`, 중고거래마켓)가 남아 있습니다.
- 매너온도 증감(후기 1건당 ±0.5)과 반응형 글자 크기 값은 임시 정책 값입니다. 확정 전에 조정할 수 있습니다.
- SQL은 아직 실제 Postgres에서 실행하지 않았습니다.

## 다음 단계

1. 캔버스 시각 점검과 수정
2. 앱 이름·패키지 ID 확정 (`com.nomad.dongnejangter` 등)
3. 개발용 Supabase 프로젝트에 마이그레이션 적용과 RLS 테스트
4. 웹과 Flutter 구현 레포에서 토큰 생성 스크립트 실행
