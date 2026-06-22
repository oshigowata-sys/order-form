#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MeguRee DB後方互換チェッカー（父親画面 凍結セーフティ）

目的:
    DB変更(migration)が「既存の項目/処理を壊していないか」を機械的に判定する。
    凍結した父親画面は共通版と同じDBに繋がるため、項目の削除・改名・型変更・
    処理(関数)の引数/戻り値変更があると父親画面が突然壊れる。それを事前に止める。

判定ルール:
    - 基準(schema-baseline.psv)に在った行が現状に無い  → 破壊的(削除/改名)   ← NG
    - 同じ項目/処理で sig(指紋) が変わった               → 破壊的(型/引数/戻り変更) ← NG
    - 現状にだけ在る行(基準に無い)                       → 追加 = OK（情報表示のみ）

使い方:
    1) db-contract/snapshot-query.sql を Supabase で実行
    2) 返ってきた文字列を db-contract/_current.psv に保存
    3) python db-contract/check-compat.py
       （引数で明示も可: python check-compat.py <baseline.psv> <current.psv>）

戻り値: 破壊的変更が1件でもあれば exit 1（=mig200禁止）、無ければ exit 0。
"""
import sys
import os

# Windowsコンソール(cp932)でもJapanese/記号が落ちないようUTF-8出力に固定
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))


def load(path):
    """ kind|obj|member|sig の行を {(kind,obj,member): sig} に読む。# と空行は無視。"""
    items = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n").rstrip("\r")
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if len(parts) < 4:
                continue
            kind, obj, member, sig = parts[0], parts[1], parts[2], parts[3]
            items[(kind, obj, member)] = sig
    return items


def main():
    baseline_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "schema-baseline.psv")
    current_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "_current.psv")

    if not os.path.exists(current_path):
        print("ERROR: 現状ファイルが無い: %s" % current_path)
        print("  → snapshot-query.sql を Supabase で実行し、結果を _current.psv に保存してから実行してください。")
        sys.exit(2)

    base = load(baseline_path)
    cur = load(current_path)

    removed = []   # 削除/改名(=破壊的)
    changed = []   # 型/引数/戻り値変更(=破壊的)
    for key, sig in base.items():
        if key not in cur:
            removed.append(key)
        elif cur[key] != sig:
            changed.append(key)

    added = [k for k in cur if k not in base]  # 追加(OK)

    def fmt(k):
        kind, obj, member = k
        return "%-8s %s.%s" % (kind, obj, member if member else "(引数なし)")

    print("=== MeguRee DB後方互換チェック ===")
    print("基準: %s (%d項目)" % (os.path.basename(baseline_path), len(base)))
    print("現状: %s (%d項目)" % (os.path.basename(current_path), len(cur)))
    print("")

    if added:
        print("[追加 / OK] %d件 ― 追加は安全です:" % len(added))
        for k in sorted(added):
            print("  + " + fmt(k))
        print("")

    breaking = removed + changed
    if not breaking:
        print("[OK] 破壊的変更ナシ。凍結した父親画面は壊れません。migrationを進めてOK。")
        sys.exit(0)

    print("[NG] 破壊的変更 %d件 ― このまま本番に当てると凍結画面が壊れます:" % len(breaking))
    for k in sorted(removed):
        print("  - 削除/改名: " + fmt(k))
    for k in sorted(changed):
        print("  ! 型/引数/戻り変更: " + fmt(k))
    print("")
    print("対処: 既存項目/処理は触らず『追加だけ』にしてください。どうしても変える必要があれば")
    print("      新カラム/新関数を足す形にし、旧いものは残す（add-only）。")
    sys.exit(1)


if __name__ == "__main__":
    main()
