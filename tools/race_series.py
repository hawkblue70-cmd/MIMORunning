#!/usr/bin/env python3
"""대회 DB(RaceDetector.swift 안 CSV)에 series 칸을 채운다.

규칙: 이름에서 연도(20xx, 20xx년)·회차(제N회, (N회))·띄어쓰기·끝의 '대회'를 떼어 키를 만든다.
같은 키 = 같은 대회. 이름이 실제로 바뀐 대회는 race_series_overrides.tsv(이름<TAB>키)로 지정한다.

사용:
  python3 tools/race_series.py            # series 칸을 다시 채워 파일을 고친다
  python3 tools/race_series.py --check    # 고치지 않고 결과만 출력
  python3 tools/race_series.py --candidates  # 사람이 확인할 후보 쌍(날짜 ±14일·출발지 5km·키 다름)
"""
import csv, io, math, re, sys, datetime as dt
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "MIMORunning/Health/RaceDetector.swift"
OVERRIDES = ROOT / "tools/race_series_overrides.tsv"
OPEN = 'private static let racesCSV = #"""\n'
CLOSE = '\n"""#'

def key(name: str) -> str:
    s = re.sub(r'(?<!\d)20\d{2}년?(?!\d)', '', name)
    s = re.sub(r'\(\s*\d+\s*회\s*\)', '', s)
    s = re.sub(r'제\s*\d+\s*회', '', s)
    s = re.sub(r'\(\s*\)', '', s)
    s = re.sub(r'\s+', '', s)
    s = re.sub(r'대회$', '', s)
    return s

def load():
    text = SWIFT.read_text(encoding="utf-8")
    a = text.index(OPEN) + len(OPEN)
    b = text.index(CLOSE, a)
    return text, a, b, list(csv.reader(io.StringIO(text[a:b])))

def overrides():
    out = {}
    if OVERRIDES.exists():
        for line in OVERRIDES.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"): continue
            name, k = line.split("\t")
            out[name.strip()] = k.strip()
    return out

def main():
    text, a, b, rows = load()
    header, body = rows[0], rows[1:]
    if header[-1] == "series":
        body = [r[:-1] if len(r) == len(header) else r for r in body]
        header = header[:-1]
    ov = overrides()
    unknown = [n for n in ov if n not in {r[0] for r in body}]
    if unknown:
        sys.exit("overrides에 DB에 없는 이름: " + ", ".join(unknown))
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(header + ["series"])
    series = []
    for r in body:
        s = ov.get(r[0], key(r[0]))
        series.append((r, s))
        w.writerow(r + [s])
    if "--candidates" in sys.argv:
        pts = []
        for r, s in series:
            try: pts.append((r, s, dt.date.fromisoformat(r[1]), float(r[5]), float(r[6])))
            except (ValueError, IndexError): pass
        for r1, s1, d1, la1, ln1 in pts:
            for r2, s2, d2, la2, ln2 in pts:
                if d2.year != d1.year + 1 or s1 == s2: continue
                if r1[7] == "city" or r2[7] == "city": continue
                try:
                    gap = abs((d2.replace(year=d1.year) - d1).days)
                except ValueError:
                    gap = abs((d2 - d1).days - 365)
                if gap > 14: continue
                km = 111 * math.hypot(la1 - la2, (ln1 - ln2) * math.cos(math.radians(la1)))
                if km <= 5:
                    print(f"{r1[0]} ({r1[1]}) ↔ {r2[0]} ({r2[1]}) · {km:.1f}km")
        return
    groups = {}
    for r, s in series:
        groups.setdefault(s, set()).add(r[1][:4])
    multi = sum(1 for ys in groups.values() if len(ys) > 1)
    print(f"대회 {len(series)}줄 · 시리즈 {len(groups)}개 · 해를 넘는 시리즈 {multi}개")
    if "--check" in sys.argv: return
    new_csv = out.getvalue().rstrip("\n")
    SWIFT.write_text(text[:a] + new_csv + text[b:], encoding="utf-8")
    print("RaceDetector.swift 갱신")

if __name__ == "__main__":
    main()
