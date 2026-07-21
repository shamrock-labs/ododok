#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
config_path="${repo_root}/Config/Secrets.xcconfig"
example_path="${repo_root}/Config/Secrets.xcconfig.example"

if [[ ! -f "${config_path}" ]]; then
    cp "${example_path}" "${config_path}"
fi

# 키를 명령행 인자로 받지 않아 shell history와 프로세스 목록에 평문이 남지 않게 한다.
# 입력 중에는 문자를 표시하지 않고, 검증이 끝난 값만 gitignored 설정 파일에 저장한다.
read -r -s "dev_key?AppsFlyer Dev Key: "
print
if [[ -z "${dev_key}" || "${dev_key}" == *$'\n'* ]]; then
    print -u2 "Dev Key가 비어 있거나 올바르지 않습니다."
    exit 1
fi

# Python 프로세스에만 임시 환경 변수로 전달하고 스크립트 종료 전에 shell 변수도 해제한다.
# 파일 전체를 재생성하지 않고 AppsFlyer 항목만 교체해 다른 로컬 서비스 키를 보존한다.
APPSFLYER_INPUT_KEY="${dev_key}" python3 - "${config_path}" <<'PY'
from pathlib import Path
import os
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
dev_key = os.environ["APPSFLYER_INPUT_KEY"]
if re.fullmatch(r"[A-Za-z0-9._-]+", dev_key) is None:
    raise SystemExit("Dev Key 형식이 올바르지 않습니다.")

values = {
    "APPSFLYER_DEV_KEY": dev_key,
    "APPSFLYER_APP_ID": "6784962920",
}

for name, value in values.items():
    line = f"{name} = {value}"
    pattern = rf"^{re.escape(name)}\s*=.*$"
    if re.search(pattern, text, flags=re.MULTILINE):
        text = re.sub(pattern, line, text, flags=re.MULTILINE)
    else:
        text = text.rstrip() + "\n" + line + "\n"

path.write_text(text)
PY

unset dev_key
print "Config/Secrets.xcconfig에 AppsFlyer 로컬 설정을 저장했습니다."
