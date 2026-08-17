#!/usr/bin/env python3
"""삭제된 파일이 정의하고 있던 타입이 아직 참조되는지 검사합니다.

왜 필요한가.
  샌드박스에 iOS SDK 가 없어서 검증을 swiftc -parse 로만 합니다.
  -parse 는 문법만 봅니다. 이름 해석을 하지 않습니다.
  그래서 "정의가 사라진 타입을 계속 쓰는" 상태를 통과시킵니다.
  실제로 이번에 PhotoSpotSearchError 가 그렇게 빠졌습니다.
  GeminiRecommendationService.swift 안에 정의되어 있었는데, 그 파일을
  AI 코드로 보고 지웠고, 남은 두 서비스가 계속 그 타입을 씁니다.

무엇을 하는가.
  주어진 커밋 범위에서 삭제된 .swift 파일을 찾고,
  그 파일이 정의했던 최상위 이름을 뽑아,
  현재 트리에서 아직 쓰이는지 봅니다.

사용법
  python3 check_orphan_refs.py <base-commit>
"""
import re
import subprocess
import sys

TOP_LEVEL = re.compile(
    r"^(?:public |internal |private |fileprivate |final |@\w+\s+)*"
    r"(?:enum|struct|class|actor|protocol|typealias)\s+([A-Za-z_][\w]*)",
    re.MULTILINE,
)


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def deleted_swift_files(base):
    out = run(["git", "diff", "--diff-filter=D", "--name-only", base, "HEAD"])
    return [p for p in out.split("\n") if p.endswith(".swift")]


def definitions_in(path, base):
    src = run(["git", "show", "%s:%s" % (base, path)])
    return sorted(set(TOP_LEVEL.findall(src)))


def grep(pattern):
    result = subprocess.run(
        ["grep", "-rn", pattern, "--include=*.swift", "Viewfinder"],
        capture_output=True, text=True,
    )
    hits = []
    for line in result.stdout.split("\n"):
        if not line.strip():
            continue
        try:
            _path, _no, code = line.split(":", 2)
        except ValueError:
            continue
        stripped = code.strip()
        # 주석은 참조가 아닙니다. 삭제 경위를 설명하는 주석에 이름이
        # 남아 있는 경우가 많아서 이것을 빼지 않으면 전부 오탐이 됩니다.
        if stripped.startswith("//") or stripped.startswith("*"):
            continue
        hits.append(line)
    return hits


def is_defined_now(name):
    """현재 트리에 이 이름의 정의가 있는지.

    삭제한 파일 안에 있던 타입을 다른 파일로 옮겨 되살리는 경우가 있습니다.
    그 경우는 문제가 아니므로, 참조가 있어도 정의가 있으면 통과시킵니다.
    이 확인이 없으면 되살린 타입까지 계속 고아로 보고합니다.
    """
    pattern = (r"^\(public \|internal \|private \|fileprivate \|final \|@\w* \)*"
               r"\(enum\|struct\|class\|actor\|protocol\|typealias\) %s\b" % name)
    return bool(grep(pattern))


def references(name):
    return grep(r"\b%s\b" % name)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    base = sys.argv[1]

    deleted = deleted_swift_files(base)
    if not deleted:
        print("삭제된 Swift 파일이 없습니다.")
        return

    print("삭제된 파일 %d개를 검사합니다.\n" % len(deleted))
    problems = 0
    for path in deleted:
        names = definitions_in(path, base)
        print("── %s" % path)
        if not names:
            print("   최상위 정의 없음")
            continue
        for name in names:
            if is_defined_now(name):
                print("   ok  %s  (다른 파일에 정의가 있습니다)" % name)
                continue

            hits = references(name)
            if hits:
                problems += 1
                print("   [고아 참조] %s — 정의가 없는데 %d곳에서 씁니다" % (name, len(hits)))
                for h in hits[:6]:
                    print("       %s" % h[:110])
            else:
                print("   ok  %s" % name)
        print()

    if problems:
        sys.exit("고아 참조 %d건. 빌드가 깨집니다." % problems)
    print("고아 참조 없음.")


if __name__ == "__main__":
    main()
