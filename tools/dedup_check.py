#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""뉴스 아카이브 중복 점검 도구.

사용법:
  # 새로 작성한 회차 파일이 과거 회차와 겹치는지 점검
  python3 tools/dedup_check.py news/archive/2026-09-21.json

  # 저장 전, 후보 기사(제목/URL)를 바로 점검
  python3 tools/dedup_check.py --title "가덕도신공항 협의체 첫 회의" --url https://example.com/a

  # 최근 N일치 아카이브에 담긴 제목 목록 출력(수집 전 참고용)
  python3 tools/dedup_check.py --list 14

종료코드: 중복이 발견되면 1, 없으면 0.
"""
import argparse
import json
import os
import re
import sys
from datetime import date, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARCHIVE_DIR = os.path.join(ROOT, "news", "archive")

# 제목 유사도 임계값 — 이 값 이상이면 같은 이슈로 간주
SIM_THRESHOLD = 0.30
# 전체 제목의 이 비율 이상에 나타나는 토큰은 변별력이 없다고 보고 제외
COMMON_TOKEN_RATIO = 0.30


def norm_url(url):
    if not url:
        return ""
    u = url.strip().lower()
    u = re.sub(r"^https?://", "", u)
    u = re.sub(r"^(www|m|biz|v|news)\.", "", u)
    u = u.split("#")[0].rstrip("/")
    return u


def tokens(title):
    if not title:
        return set()
    t = re.sub(r"\[[^\]]*\]", " ", title)          # [제도] 같은 분류 태그 제거
    t = re.sub(r"[^0-9A-Za-z가-힣]+", " ", t)
    out = set()
    for w in t.split():
        if len(w) < 2:
            continue
        if re.fullmatch(r"\d+", w):                 # 숫자만 있는 토큰 제외
            continue
        out.add(w)
    return out


def load_archive(exclude_path=None):
    """아카이브 전체를 [(date, title, url, tokenset)] 로 읽는다."""
    rows = []
    if not os.path.isdir(ARCHIVE_DIR):
        return rows
    ex = os.path.abspath(exclude_path) if exclude_path else None
    for name in sorted(os.listdir(ARCHIVE_DIR)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(ARCHIVE_DIR, name)
        if ex and os.path.abspath(path) == ex:
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception as e:  # 깨진 파일이 전체 점검을 막지 않도록
            print("  ! 읽기 실패: %s (%s)" % (name, e), file=sys.stderr)
            continue
        d = data.get("date") or name[:-5]
        for it in data.get("items", []):
            rows.append((d, it.get("title", ""), it.get("url", ""), tokens(it.get("title", ""))))
    return rows


def common_tokens(rows):
    """'건설', '국토부'처럼 거의 모든 제목에 나오는 토큰을 골라낸다."""
    if not rows:
        return set()
    df = {}
    for _, _, _, ts in rows:
        for w in ts:
            df[w] = df.get(w, 0) + 1
    limit = max(2, int(len(rows) * COMMON_TOKEN_RATIO))
    return {w for w, c in df.items() if c >= limit}


def similarity(a, b, stop):
    a = a - stop
    b = b - stop
    if not a or not b:
        return 0.0
    return len(a & b) / float(len(a | b))


def check(cand_title, cand_url, rows, stop, since=None):
    """(사유, 과거회차날짜, 과거제목) 리스트를 반환. 비어 있으면 새 이슈."""
    hits = []
    cu = norm_url(cand_url)
    ct = tokens(cand_title)
    for d, title, url, ts in rows:
        if since and d < since:
            continue
        if cu and cu == norm_url(url):
            hits.append(("동일 URL", d, title))
            continue
        sim = similarity(ct, ts, stop)
        if sim >= SIM_THRESHOLD:
            hits.append(("제목 유사도 %.2f" % sim, d, title))
    return hits


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("file", nargs="?", help="점검할 회차 JSON 경로")
    ap.add_argument("--title", help="후보 기사 제목")
    ap.add_argument("--url", default="", help="후보 기사 URL")
    ap.add_argument("--list", type=int, metavar="N", help="최근 N일 아카이브 제목 목록 출력")
    ap.add_argument("--since", help="이 날짜(YYYY-MM-DD) 이후 회차만 비교")
    args = ap.parse_args()

    if args.list:
        rows = load_archive()
        cutoff = (date.today() - timedelta(days=args.list)).isoformat()
        shown = [r for r in rows if r[0] >= cutoff]
        print("최근 %d일(%s 이후) 아카이브 수록 기사 %d건" % (args.list, cutoff, len(shown)))
        for d, title, url, _ in shown:
            print("  [%s] %s" % (d, title))
            if url:
                print("          %s" % url)
        return 0

    if args.title:
        rows = load_archive()
        stop = common_tokens(rows)
        hits = check(args.title, args.url, rows, stop, args.since)
        if not hits:
            print("OK — 과거 회차와 겹치지 않는 새 이슈입니다.")
            return 0
        print("중복 의심:")
        for reason, d, title in hits:
            print("  · %s ← [%s] %s" % (reason, d, title))
        return 1

    if not args.file:
        ap.print_help()
        return 2

    data = json.load(open(args.file, encoding="utf-8"))
    rows = load_archive(exclude_path=args.file)
    stop = common_tokens(rows)
    dup = 0
    print("점검 대상: %s (%d건)" % (args.file, len(data.get("items", []))))
    for it in data.get("items", []):
        title = it.get("title", "")
        hits = check(title, it.get("url", ""), rows, stop, args.since)
        if it.get("followup"):
            mark = "FOLLOWUP"
        elif hits:
            mark = "DUP"
            dup += 1
        else:
            mark = "NEW"
        print("\n[%s] %s" % (mark, title[:90]))
        for reason, d, past in hits:
            print("    ← %s / [%s] %s" % (reason, d, past[:80]))
    print("\n결과: 신규 %d건, 중복 의심 %d건" % (len(data.get("items", [])) - dup, dup))
    if dup:
        print("중복 건은 제외하거나, 실질적 후속 진전이 있는 경우에만")
        print("제목 앞에 '[후속]'을 붙이고 항목에 \"followup\": true 를 넣어 남길 것.")
    return 1 if dup else 0


if __name__ == "__main__":
    sys.exit(main())
