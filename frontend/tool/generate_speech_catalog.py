"""검수한 말투 JSON을 Flutter 상수로 만들고 선택한 개인 백엔드와 공유한다."""
import argparse
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'lib/src/data/speech_catalog.json'
data = json.loads(source.read_text())
(root / 'lib/src/data/speech_catalog.dart').write_text(
    '// 자동 생성: speech_catalog.json 수정 후 tool/generate_speech_catalog.py 실행.\n'
    'const Map<String, dynamic> speechCatalog = '
    + json.dumps(data, ensure_ascii=False, indent=2) + ';\n')
parser = argparse.ArgumentParser()
parser.add_argument('--backend-repo', type=Path)
args = parser.parse_args()
if args.backend_repo:
    (args.backend_repo / 'server/app/speech_catalog.json').write_bytes(source.read_bytes())
