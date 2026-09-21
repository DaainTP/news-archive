# news-archive

CM(건설사업관리) 제안서용 뉴스 검색 결과 및 요약 저장소.

- `news/latest.json` — 최신 회차 (통합포털이 읽는 파일)
- `news/archive/YYYY-MM-DD.json` — 회차별 아카이브
- `tools/dedup_check.py` — 과거 회차와의 중복 점검 도구

수집·작성 규칙은 [CLAUDE.md](CLAUDE.md) 참고.

```bash
# 새 회차 저장 전 중복 점검
python3 tools/dedup_check.py news/archive/2026-09-21.json

# 최근 2주간 이미 다룬 기사 목록
python3 tools/dedup_check.py --list 14
```
