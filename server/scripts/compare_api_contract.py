"""프론트의 기존 계약 스냅샷과 실제 팀 명세를 비교한다. 스냅샷은 덮어쓰지 않는다."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    actual = json.loads((ROOT / "output/diagnosis/team-openapi.json").read_text(encoding="utf-8"))
    frontend = json.loads(
        (ROOT / "frontend/test/contract/openapi.json").read_text(encoding="utf-8")
    )
    paths = {}
    for path, methods in frontend["paths"].items():
        missing = sorted(set(methods) - set(actual["paths"].get(path, {})))
        if missing:
            paths[path] = missing
    schemas = {}
    for name in ("CharacterOut", "GenerationOut", "ProfileOut", "MessageOut"):
        expected = frontend["components"]["schemas"].get(name, {}).get("properties", {})
        implemented = actual["components"]["schemas"].get(name, {}).get("properties", {})
        schemas[name] = {
            "onlyFrontend": sorted(set(expected) - set(implemented)),
            "onlyBackend": sorted(set(implemented) - set(expected)),
        }
    report = {
        "frontendMethodsMissingFromBackend": paths,
        "responseProperties": schemas,
        "saveRequest": actual["components"]["schemas"]["SaveFriendIn"],
    }
    output = ROOT / "output/diagnosis/contract-diff.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
