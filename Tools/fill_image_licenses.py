#!/usr/bin/env python3
"""시드 사진의 저작자·라이선스를 위키미디어에서 받아 채웁니다.

왜 필요한가
  시드 131곳 중 사진이 있는 52곳은 전부 위키미디어 커먼즈(49)와
  플리커(3)에서 온 이미지입니다. 확인된 라이선스는 CC BY-SA 11개,
  CC BY 3개, CC0 1개입니다. CC BY 와 CC BY-SA 는 저작자 표기가
  의무입니다.

  그런데 지금 상태가 이렇습니다.
    imageCredit    23곳만 채워짐  → 29곳은 표기 없이 쓰는 중
    imageLicense   15곳만 채워짐  → 37곳은 라이선스 불명
    imageSourceURL 23곳만 채워짐

  앱은 상세 화면에서 imageCredit 이 있을 때만 표기를 보여줍니다.
  즉 29곳은 아무 표기 없이 사진이 노출됩니다. 라이선스 위반입니다.

왜 스크립트인가
  이 저장소를 다루는 샌드박스에는 외부 네트워크가 없습니다.
  위키미디어 API 와 파일 페이지 모두 403 으로 막힙니다.
  그래서 조회는 네트워크가 있는 로컬 맥에서 실행해야 합니다.

사용법
  python3 Tools/fill_image_licenses.py            확인만 (파일을 바꾸지 않음)
  python3 Tools/fill_image_licenses.py --write    시드에 반영

원칙
  표기할 수 없는 사진은 쓰지 않습니다.
  조회에 실패하거나 저작자를 알 수 없는 항목은 --write 로도 채우지 않고
  목록으로 보고합니다. 그 사진은 지우거나 다른 것으로 바꿔야 합니다.
"""
import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request

SEED = os.path.join(os.path.dirname(__file__), "..", "Viewfinder", "Data", "photo_spots_seed.json")
API = "https://commons.wikimedia.org/w/api.php"
# 위키미디어는 설명 없는 User-Agent 요청을 거부합니다.
USER_AGENT = "ViewfinderSeedLicenseFiller/1.0 (photo spot app; contact via repository)"

TAG_RE = re.compile(r"<[^>]+>")


def strip_html(value):
    text = TAG_RE.sub("", value or "")
    return " ".join(text.split()).strip()


def commons_file_name(image_url):
    """위키미디어 URL 에서 커먼즈 파일 이름을 뽑습니다.

    두 가지 형태가 있습니다.
      upload.wikimedia.org/wikipedia/commons/5/57/이름.jpg
      commons.wikimedia.org/wiki/Special:FilePath/이름.jpg
    """
    parsed = urllib.parse.urlparse(image_url)
    if "wikimedia.org" not in parsed.netloc:
        return None

    path = urllib.parse.unquote(parsed.path)
    if "/Special:FilePath/" in path:
        return path.split("/Special:FilePath/", 1)[1]

    parts = [p for p in path.split("/") if p]
    if not parts:
        return None
    # 썸네일 URL 은 .../commons/thumb/5/57/이름.jpg/800px-이름.jpg 형태입니다.
    if "thumb" in parts:
        return parts[-2]
    return parts[-1]


def fetch_metadata(file_names):
    """커먼즈에서 extmetadata 를 배치로 받습니다. 한 번에 50개까지."""
    result = {}
    for start in range(0, len(file_names), 50):
        batch = file_names[start:start + 50]
        params = {
            "action": "query",
            "titles": "|".join("File:" + n for n in batch),
            "prop": "imageinfo",
            "iiprop": "extmetadata",
            "format": "json",
            "formatversion": "2",
        }
        url = API + "?" + urllib.parse.urlencode(params)
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)

        for page in payload.get("query", {}).get("pages", []):
            title = page.get("title", "")
            name = title[len("File:"):] if title.startswith("File:") else title
            if page.get("missing"):
                result[name] = None
                continue
            info = (page.get("imageinfo") or [{}])[0]
            meta = info.get("extmetadata") or {}

            def value(key):
                entry = meta.get(key)
                return strip_html(entry.get("value")) if entry else ""

            result[name] = {
                "artist": value("Artist"),
                "license": value("LicenseShortName"),
                "attribution": value("Attribution"),
                "credit": value("Credit"),
                "usage_terms": value("UsageTerms"),
            }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="시드 파일에 반영")
    args = parser.parse_args()

    with open(SEED, encoding="utf-8") as handle:
        data = json.load(handle)
    spots = data if isinstance(data, list) else data.get("spots")
    if spots is None:
        sys.exit("시드 형식을 알 수 없습니다.")

    targets = []
    non_wikimedia = []
    for spot in spots:
        image_url = spot.get("imageURL")
        if not image_url:
            continue
        name = commons_file_name(image_url)
        if name:
            targets.append((spot, name))
        else:
            non_wikimedia.append(spot)

    print("사진 있는 장소 %d곳" % (len(targets) + len(non_wikimedia)))
    print("  위키미디어 %d곳 → 조회 대상" % len(targets))
    print("  그 외 %d곳 → 직접 확인 필요" % len(non_wikimedia))
    for spot in non_wikimedia:
        print("      %-22s %s" % (spot["name"][:20], spot["imageURL"][:70]))
    print()

    unique_names = sorted({name for _spot, name in targets})
    print("커먼즈 파일 %d개를 조회합니다..." % len(unique_names))
    try:
        metadata = fetch_metadata(unique_names)
    except Exception as error:                      # noqa: BLE001
        sys.exit("조회 실패: %s\n네트워크가 있는 환경에서 실행해야 합니다." % error)

    filled = 0
    unresolved = []
    for spot, name in targets:
        meta = metadata.get(name)
        artist = (meta or {}).get("artist", "")
        license_name = (meta or {}).get("license", "")

        if not meta or not artist or not license_name:
            unresolved.append((spot, name, meta))
            continue

        source_url = "https://commons.wikimedia.org/wiki/File:" + urllib.parse.quote(name)
        if args.write:
            spot["imageCredit"] = artist
            spot["imageLicense"] = license_name
            spot["imageSourceURL"] = source_url
        filled += 1

    print()
    print("표기를 채울 수 있는 사진  %d곳" % filled)
    print("표기를 확정할 수 없는 사진 %d곳" % len(unresolved))
    for spot, name, meta in unresolved:
        reason = "조회 결과 없음" if not meta else "저작자 또는 라이선스 비어 있음"
        print("    %-22s %-46s %s" % (spot["name"][:20], name[:44], reason))

    if unresolved:
        print()
        print("위 사진들은 저작자 표기를 만들 수 없습니다.")
        print("표기할 수 없는 사진은 쓰지 않는 것이 원칙이므로,")
        print("해당 장소의 imageURL 을 비우거나 다른 사진으로 바꿔야 합니다.")

    if args.write:
        with open(SEED, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        print()
        print("시드에 %d곳을 반영했습니다: %s" % (filled, os.path.relpath(SEED)))
    else:
        print()
        print("확인만 했습니다. 반영하려면 --write 를 붙이세요.")


if __name__ == "__main__":
    main()
