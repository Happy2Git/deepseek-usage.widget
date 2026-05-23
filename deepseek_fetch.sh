#!/bin/bash
set -u

WIDGET_DIR="$(cd "$(dirname "$0")" && pwd)"
API_URL="https://api.deepseek.com/user/balance"
SERVICE_NAME="ubersicht-dpsk-api"
MAX_HISTORY=90

SECURITY_BIN="${DEEPSEEK_SECURITY_BIN:-/usr/bin/security}"
CURL_BIN="${DEEPSEEK_CURL_BIN:-/usr/bin/curl}"
HISTORY_FILE="${DEEPSEEK_HISTORY_FILE:-$WIDGET_DIR/data/history.json}"
USAGE_ROOT="${DEEPSEEK_USAGE_ROOT:-$WIDGET_DIR/data}"

json_error() {
  ERROR_MESSAGE="$1" /usr/bin/python3 - <<'PY'
import json
import os

print(json.dumps({
    "ok": False,
    "error": os.environ["ERROR_MESSAGE"],
}, ensure_ascii=False))
PY
}

api_key="$("$SECURITY_BIN" find-generic-password -s "$SERVICE_NAME" -w 2>&1)"
key_status=$?
api_key="$(printf '%s' "$api_key" | sed -e 's/[[:space:]]*$//')"

if [ "$key_status" -ne 0 ] || [ -z "$api_key" ] || [[ "$api_key" == security:* ]]; then
  json_error "Missing API key: ${api_key:-empty keychain result}"
  exit 0
fi

api_response="$("$CURL_BIN" -fsS "$API_URL" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $api_key" 2>&1)"
curl_status=$?

if [ "$curl_status" -ne 0 ]; then
  json_error "DeepSeek request failed: $api_response"
  exit 0
fi

API_RESPONSE="$api_response" HISTORY_FILE="$HISTORY_FILE" MAX_HISTORY="$MAX_HISTORY" USAGE_ROOT="$USAGE_ROOT" /usr/bin/python3 - <<'PY'
import csv
import json
import os
import re
import shutil
import zipfile
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

def emit_error(message):
    print(json.dumps({"ok": False, "error": message}, ensure_ascii=False))

try:
    payload = json.loads(os.environ["API_RESPONSE"])
except Exception as exc:
    emit_error(f"DeepSeek returned invalid JSON: {exc}")
    raise SystemExit(0)

info = (payload.get("balance_infos") or [{}])[0] or {}
now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0

point = {
    "t": now,
    "total": as_float(info.get("total_balance")),
    "granted": as_float(info.get("granted_balance")),
    "topped_up": as_float(info.get("topped_up_balance")),
    "available": payload.get("is_available") is True,
}

history_path = Path(os.environ["HISTORY_FILE"])
history_path.parent.mkdir(parents=True, exist_ok=True)

try:
    history = json.loads(history_path.read_text()) if history_path.exists() else []
    if not isinstance(history, list):
        history = []
except Exception:
    history = []

max_history = int(os.environ.get("MAX_HISTORY", "90"))
history = history[-max_history:]

last = history[-1] if history else None
if not last or last.get("total") != point["total"]:
    history.append(point)
    history = history[-max_history:]
    history_path.write_text(json.dumps(history, separators=(",", ":")))

def usage_dir_name_from_text(text):
    match = re.search(r"usage_data_(\d{4})_(\d{1,2})", text)
    if match:
        return f"usage_data_{int(match.group(1))}_{int(match.group(2))}"
    match = re.search(r"amount-(\d{4})-(\d{1,2})\.csv$", text)
    if match:
        return f"usage_data_{int(match.group(1))}_{int(match.group(2))}"
    return None

def import_usage_exports():
    usage_root = Path(os.environ["USAGE_ROOT"])
    if not usage_root.exists():
        return

    usage_root.mkdir(parents=True, exist_ok=True)
    zip_candidates = sorted(
        [item for item in usage_root.iterdir() if item.is_file() and item.suffix.lower() == ".zip"],
        key=lambda item: (item.stat().st_mtime, item.name),
    )
    if not zip_candidates:
        return

    latest_zip = zip_candidates[-1]
    try:
        with zipfile.ZipFile(latest_zip) as archive:
            names = [name for name in archive.namelist() if not name.endswith("/")]
            usage_name = usage_dir_name_from_text(latest_zip.name)
            if not usage_name:
                for name in names:
                    usage_name = usage_dir_name_from_text(name)
                    if usage_name:
                        break
            if not usage_name:
                return

            csv_names = [
                name for name in names
                if Path(name).name.startswith(("amount-", "cost-")) and Path(name).suffix.lower() == ".csv"
            ]
            if not csv_names:
                return

            for old_dir in usage_root.glob("usage_data_*"):
                if old_dir.is_dir():
                    shutil.rmtree(old_dir)

            target_dir = usage_root / usage_name
            target_dir.mkdir(parents=True, exist_ok=True)
            for name in csv_names:
                target_path = target_dir / Path(name).name
                with archive.open(name) as source, target_path.open("wb") as target:
                    shutil.copyfileobj(source, target)
    except zipfile.BadZipFile:
        return
    finally:
        for zip_path in zip_candidates:
            try:
                zip_path.unlink()
            except OSError:
                pass

def parse_amount_csv():
    import_usage_exports()

    usage_root = Path(os.environ["USAGE_ROOT"])
    def usage_dir_key(path):
        parts = path.name.split("_")
        try:
            return (int(parts[-2]), int(parts[-1]))
        except Exception:
            return (0, 0)

    candidates = sorted(usage_root.glob("usage_data_*"), key=usage_dir_key)
    if not candidates:
        return None

    latest_dir = candidates[-1]
    amount_files = sorted(latest_dir.glob("amount-*.csv"))
    if not amount_files:
        return None

    rows = []
    for csv_path in amount_files:
        try:
            with csv_path.open(newline="", encoding="utf-8-sig") as handle:
                reader = csv.DictReader(handle)
                for row in reader:
                    try:
                        row_date = date.fromisoformat(row.get("utc_date", ""))
                    except ValueError:
                        continue
                    try:
                        amount = int(Decimal(row.get("amount") or "0"))
                    except Exception:
                        amount = 0
                    try:
                        price = Decimal(row.get("price") or "0")
                    except Exception:
                        price = Decimal("0")
                    rows.append({
                        "date": row_date,
                        "model": row.get("model") or "unknown",
                        "name": row.get("api_key_name") or "Unnamed key",
                        "key": row.get("api_key") or "",
                        "type": row.get("type") or "unknown",
                        "amount": amount,
                        "cost": price * Decimal(amount),
                    })
        except Exception:
            continue

    if not rows:
        return None

    latest_date = max(row["date"] for row in rows)

    def empty_total():
        return {
            "tokens": 0,
            "requests": 0,
            "cost": Decimal("0"),
            "types": defaultdict(int),
            "models": defaultdict(int),
            "keys": {},
        }

    def add_row(total, row):
        if row["type"] == "request_count":
            total["requests"] += row["amount"]
        else:
            total["tokens"] += row["amount"]
            total["types"][row["type"]] += row["amount"]
            total["models"][row["model"]] += row["amount"]
        total["cost"] += row["cost"]

        key_id = row["key"] or row["name"]
        key_total = total["keys"].setdefault(key_id, {
            "name": row["name"],
            "key": row["key"],
            "tokens": 0,
            "requests": 0,
            "cost": Decimal("0"),
            "types": defaultdict(int),
            "models": defaultdict(int),
        })
        if row["type"] == "request_count":
            key_total["requests"] += row["amount"]
        else:
            key_total["tokens"] += row["amount"]
            key_total["types"][row["type"]] += row["amount"]
            key_total["models"][row["model"]] += row["amount"]
        key_total["cost"] += row["cost"]

    def clean_decimal(value):
        return float(value.quantize(Decimal("0.000001")))

    def clean_counts(mapping):
        return dict(sorted(mapping.items(), key=lambda item: item[0]))

    def summarize(days):
        start = latest_date - timedelta(days=days - 1)
        total = empty_total()
        for row in rows:
            if start <= row["date"] <= latest_date:
                add_row(total, row)

        keys = sorted(total["keys"].values(), key=lambda item: item["tokens"], reverse=True)
        top_keys = keys[:3]
        def clean_key(key):
            return {
                "name": key["name"],
                "key": key["key"],
                "tokens": key["tokens"],
                "requests": key["requests"],
                "cost": clean_decimal(key["cost"]),
                "types": clean_counts(key["types"]),
                "models": clean_counts(key["models"]),
            }
        return {
            "start": start.isoformat(),
            "end": latest_date.isoformat(),
            "tokens": total["tokens"],
            "requests": total["requests"],
            "cost": clean_decimal(total["cost"]),
            "types": clean_counts(total["types"]),
            "models": clean_counts(total["models"]),
            "keys": [clean_key(key) for key in keys],
            "topKeys": [clean_key(key) for key in top_keys],
        }

    return {
        "source": latest_dir.name,
        "latestDate": latest_date.isoformat(),
        "windows": {
            "today": summarize(1),
            "7d": summarize(7),
            "30d": summarize(30),
        },
    }

print(json.dumps({
    "ok": True,
    "current": point,
    "history": history,
    "usage": parse_amount_csv(),
    "updatedAt": now,
}, ensure_ascii=False))
PY
