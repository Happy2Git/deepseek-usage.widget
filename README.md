# DeepSeek Usage Widget

Ubersicht widget that displays your DeepSeek account balance on the desktop.

## Features

- Current balance (CNY)
- Top-up / granted balance breakdown
- 1-day / 7-day / 30-day token and cost summary from DeepSeek usage CSV exports
- Top 3 API keys by 30-day token usage, including cache-hit, cache-miss, output, and request counts
- 30-day balance trend with sparkline chart
- 30-minute auto-refresh
- macOS translucent dark UI (Linear / Raycast style)

## Setup

### 1. Store API Key in macOS Keychain

```bash
security add-generic-password -a "$USER" -s "ubersicht-dpsk-api" -w "YOUR_DEEPSEEK_API_KEY" -U
```

Verify it was stored correctly:

```bash
security find-generic-password -s "ubersicht-dpsk-api" -w
```

### 2. Reload Widget

In the Übersicht menu bar icon, click **Reload Widgets**, or run:

```bash
osascript -e 'tell application "Übersicht" to refresh'
```

### 3. Usage CSV Exports

Download the DeepSeek usage export for the month and move the `.zip` into this widget's `data/` folder. On the next refresh, the widget imports the zip, removes older `usage_data_*` folders, deletes the imported zip, and then reads the newest usage data.

You can also manually place the extracted folder under `data/`, for example:

```text
data/usage_data_2026_5/
├── amount-2026-5.csv
└── cost-2026-5.csv
```

Supported imports:

- `data/usage_data_2026_5.zip`
- Any `data/*.zip` containing `amount-YYYY-M.csv` and `cost-YYYY-M.csv`
- A manually extracted `data/usage_data_2026_5/` folder

Per-key cost is calculated from `amount * price` in `amount-*.csv`.

## File Structure

```
deepseek-usage.widget/
├── index.jsx      # Main widget code
├── deepseek_fetch.sh  # Reads Keychain, syncs usage exports, calls DeepSeek, writes history
├── test_deepseek_fetch.sh
├── data/
│   └── history.json   # Auto-generated balance history
└── README.md
```

## Widget Position

Default: bottom-right corner. Edit `right` / `bottom` values in the `container` style within `index.jsx` to reposition.
