#!/bin/bash
set -euo pipefail

WIDGET_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$WIDGET_DIR/deepseek_fetch.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_json_field() {
  local json="$1"
  local expr="$2"
  local expected="$3"
  JSON_INPUT="$json" EXPR="$expr" EXPECTED="$expected" /usr/bin/python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["JSON_INPUT"])
value = data
for part in os.environ["EXPR"].split("."):
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value[part]

if str(value) != os.environ["EXPECTED"]:
    print(f"expected {os.environ['EXPR']}={os.environ['EXPECTED']}, got {value}", file=sys.stderr)
    sys.exit(1)
PY
}

write_usage_csv() {
  local usage_dir="$1"
  mkdir -p "$usage_dir"
  cat > "$usage_dir/amount-2026-5.csv" <<'CSV'
user_id,utc_date,model,api_key_name,api_key,type,price,amount
u1,2026-05-23,deepseek-v4-pro,Main,test-key-main,output_tokens,0.000006,100
u1,2026-05-23,deepseek-v4-pro,Main,test-key-main,input_cache_hit_tokens,0.000000025,1000
u1,2026-05-23,deepseek-v4-pro,Main,test-key-main,input_cache_miss_tokens,0.000003,200
u1,2026-05-23,deepseek-v4-pro,Main,test-key-main,request_count,,4
u1,2026-05-22,deepseek-v4-flash,Helper,test-key-helper,output_tokens,0.000002,50
u1,2026-05-22,deepseek-v4-flash,Helper,test-key-helper,input_cache_hit_tokens,0.00000002,500
u1,2026-05-22,deepseek-v4-flash,Helper,test-key-helper,input_cache_miss_tokens,0.000001,100
u1,2026-05-22,deepseek-v4-flash,Helper,test-key-helper,request_count,,2
u1,2026-05-17,deepseek-v4-flash,OldKey,test-key-old,output_tokens,0.000002,1000
u1,2026-05-17,deepseek-v4-flash,OldKey,test-key-old,input_cache_hit_tokens,0.00000002,10000
u1,2026-05-17,deepseek-v4-flash,OldKey,test-key-old,input_cache_miss_tokens,0.000001,1000
u1,2026-05-17,deepseek-v4-flash,OldKey,test-key-old,request_count,,8
CSV
}

write_usage_zip() {
  local zip_path="$1"
  local source_dir="$TMPDIR/zip-source/usage_data_2026_5"
  rm -rf "$TMPDIR/zip-source"
  write_usage_csv "$source_dir"
  ZIP_PATH="$zip_path" SOURCE_ROOT="$TMPDIR/zip-source" /usr/bin/python3 - <<'PY'
import os
import pathlib
import zipfile

zip_path = pathlib.Path(os.environ["ZIP_PATH"])
source_root = pathlib.Path(os.environ["SOURCE_ROOT"])
zip_path.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(zip_path, "w") as zf:
    for path in source_root.rglob("*"):
        if path.is_file():
            zf.write(path, path.relative_to(source_root))
PY
}

test_success_outputs_widget_payload() {
  local security_bin="$TMPDIR/security-success"
  local curl_bin="$TMPDIR/curl-success"
  local history_file="$TMPDIR/history.json"
  local usage_root="$TMPDIR/usage"

  printf '#!/bin/bash\nprintf test-api-key\n' > "$security_bin"
  printf '%s\n' '#!/bin/bash' \
    'printf '\''{"is_available":true,"balance_infos":[{"total_balance":"12.34","granted_balance":"1.23","topped_up_balance":"11.11"}]}'\''' \
    > "$curl_bin"
  chmod +x "$security_bin" "$curl_bin"
  write_usage_csv "$usage_root/usage_data_2026_5"

  output="$(DEEPSEEK_SECURITY_BIN="$security_bin" DEEPSEEK_CURL_BIN="$curl_bin" DEEPSEEK_HISTORY_FILE="$history_file" DEEPSEEK_USAGE_ROOT="$usage_root" "$SCRIPT")"

  assert_json_field "$output" "ok" "True"
  assert_json_field "$output" "current.total" "12.34"
  assert_json_field "$output" "current.granted" "1.23"
  assert_json_field "$output" "current.topped_up" "11.11"
  assert_json_field "$output" "current.available" "True"
  assert_json_field "$output" "usage.latestDate" "2026-05-23"
  assert_json_field "$output" "usage.windows.today.tokens" "1300"
  assert_json_field "$output" "usage.windows.today.requests" "4"
  assert_json_field "$output" "usage.windows.today.cost" "0.001225"
  assert_json_field "$output" "usage.windows.7d.tokens" "13950"
  assert_json_field "$output" "usage.windows.7d.requests" "14"
  assert_json_field "$output" "usage.windows.7d.cost" "0.004635"
  assert_json_field "$output" "usage.windows.30d.topKeys.0.name" "OldKey"
  assert_json_field "$output" "usage.windows.30d.topKeys.0.tokens" "12000"
  assert_json_field "$output" "usage.windows.30d.topKeys.0.types.output_tokens" "1000"
  assert_json_field "$output" "usage.windows.30d.topKeys.1.name" "Main"
}

test_missing_key_outputs_error_payload() {
  local security_bin="$TMPDIR/security-fail"
  local curl_bin="$TMPDIR/curl-unused"

  printf '#!/bin/bash\nprintf "security: item not found" >&2\nexit 44\n' > "$security_bin"
  printf '#!/bin/bash\nexit 99\n' > "$curl_bin"
  chmod +x "$security_bin" "$curl_bin"

  output="$(DEEPSEEK_SECURITY_BIN="$security_bin" DEEPSEEK_CURL_BIN="$curl_bin" DEEPSEEK_HISTORY_FILE="$TMPDIR/missing.json" "$SCRIPT")"

  assert_json_field "$output" "ok" "False"
  assert_json_field "$output" "error" "Missing API key: security: item not found"
}

test_data_usage_zip_replaces_old_usage_folder() {
  local security_bin="$TMPDIR/security-import"
  local curl_bin="$TMPDIR/curl-import"
  local history_file="$TMPDIR/import-history.json"
  local usage_root="$TMPDIR/imported-usage"

  printf '#!/bin/bash\nprintf test-api-key\n' > "$security_bin"
  printf '%s\n' '#!/bin/bash' \
    'printf '\''{"is_available":true,"balance_infos":[{"total_balance":"12.34","granted_balance":"1.23","topped_up_balance":"11.11"}]}'\''' \
    > "$curl_bin"
  chmod +x "$security_bin" "$curl_bin"
  write_usage_csv "$usage_root/usage_data_2026_4"
  write_usage_zip "$usage_root/usage_data_2026_5.zip"

  output="$(DEEPSEEK_SECURITY_BIN="$security_bin" DEEPSEEK_CURL_BIN="$curl_bin" DEEPSEEK_HISTORY_FILE="$history_file" DEEPSEEK_USAGE_ROOT="$usage_root" "$SCRIPT")"

  test -f "$usage_root/usage_data_2026_5/amount-2026-5.csv"
  test ! -d "$usage_root/usage_data_2026_4"
  test ! -f "$usage_root/usage_data_2026_5.zip"
  assert_json_field "$output" "usage.source" "usage_data_2026_5"
  assert_json_field "$output" "usage.windows.today.tokens" "1300"
  assert_json_field "$output" "usage.windows.30d.topKeys.0.name" "OldKey"
}

test_success_outputs_widget_payload
test_missing_key_outputs_error_payload
test_data_usage_zip_replaces_old_usage_folder
printf 'deepseek_fetch tests passed\n'
