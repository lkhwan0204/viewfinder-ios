#!/usr/bin/env python3
"""표기 없이 쓰이는 사진을 찾습니다. 네트워크가 필요 없습니다.

시드의 사진은 전부 위키미디어 커먼즈와 플리커에서 왔습니다.
CC BY 와 CC BY-SA 는 저작자 표기가 의무입니다.

앱은 상세 화면에서 imageCredit 이 있을 때만 표기를 보여줍니다.
(SpotDetailView.attributionText)
따라서 imageCredit 이 빈 사진은 아무 표기 없이 노출됩니다.

이 스크립트는 그런 항목을 셉니다. 하나라도 있으면 실패로 끝냅니다.
출시 전 검사로 쓰기 위한 것입니다.

사용법
  python3 Tools/audit_image_attribution.py
"""
import json
import os
import sys
import urllib.parse

SEED = os.path.join(os.path.dirname(__file__), "..", "Viewfinder", "Data", "photo_spots_seed.json")

# 저작자 표기가 필요한 출처.
# 우리가 올린 사진(사용자 제보)은 서버에서 오고 PlaceSubmissionService 가
# imageCredit 을 채우므로 여기 해당하지 않습니다.
ATTRIBUTION_REQUIRED_HOSTS = (
    "wikimedia.org",
    "wikipedia.org",
    "staticflickr.com",
    "flickr.com",
    "unsplash.com",
    "pexels.com",
)


def needs_attribution(image_url):
    host = urllib.parse.urlparse(image_url).netloc.lower()
    return any(host.endswith(h) or h in host for h in ATTRIBUTION_REQUIRED_HOSTS)


def main():
    with open(SEED, encoding="utf-8") as handle:
        data = json.load(handle)
    spots = data if isinstance(data, list) else data.get("spots")
    if spots is None:
        sys.exit("시드 형식을 알 수 없습니다.")

    total = len(spots)
    with_photo = [s for s in spots if s.get("imageURL")]
    external = [s for s in with_photo if needs_attribution(s["imageURL"])]

    missing_credit = [s for s in external if not (s.get("imageCredit") or "").strip()]
    missing_license = [s for s in external if not (s.get("imageLicense") or "").strip()]
    missing_source = [s for s in external if not (s.get("imageSourceURL") or "").strip()]

    print("전체 장소            %d곳" % total)
    print("사진 있는 장소        %d곳" % len(with_photo))
    print("표기가 필요한 사진     %d곳" % len(external))
    print()
    print("저작자(imageCredit) 없음    %d곳   ← 표기 없이 노출 중" % len(missing_credit))
    print("라이선스(imageLicense) 없음  %d곳" % len(missing_license))
    print("출처 링크(imageSourceURL) 없음 %d곳" % len(missing_source))

    if missing_credit:
        print()
        print("저작자 표기 없이 쓰이는 장소")
        for spot in missing_credit:
            print("    %-24s %s" % (spot["name"][:22], spot["imageURL"][:64]))

    print()
    if missing_credit:
        print("표기 없이 노출되는 사진이 %d곳 있습니다." % len(missing_credit))
        print("Tools/fill_image_licenses.py 를 네트워크가 있는 환경에서 실행해")
        print("저작자와 라이선스를 채우세요. 채울 수 없는 사진은 지워야 합니다.")
        sys.exit(1)

    print("표기가 필요한 모든 사진에 저작자가 있습니다.")


if __name__ == "__main__":
    main()
