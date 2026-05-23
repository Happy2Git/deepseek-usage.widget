import { css } from "uebersicht";

export const refreshFrequency = 30 * 60 * 1000;
export const command = "./deepseek-usage.widget/deepseek_fetch.sh";

const parseOutput = (output, commandError) => {
  if (commandError) return { error: String(commandError) };
  if (!output) return { current: null, history: [], updatedAt: null, error: null };
  try {
    const payload = JSON.parse(output);
    if (!payload.ok) {
      return { current: null, history: [], updatedAt: null, error: payload.error || "Unknown error" };
    }
    return {
      current: payload.current,
      history: payload.history || [],
      usage: payload.usage,
      updatedAt: payload.updatedAt,
      error: null,
    };
  } catch (err) {
    return { current: null, history: [], updatedAt: null, error: `Invalid widget output: ${err.message}` };
  }
};

// ── Helpers ─────────────────────────────────────────────
const fmt = (n) => Number(n).toFixed(2);

const compact = (n) => {
  const value = Number(n) || 0;
  if (value >= 1e9) return `${(value / 1e9).toFixed(2)}B`;
  if (value >= 1e6) return `${(value / 1e6).toFixed(1)}M`;
  if (value >= 1e3) return `${(value / 1e3).toFixed(0)}K`;
  return String(Math.round(value));
};

const fmtCost = (n) => `¥${Number(n || 0).toFixed(2)}`;

const typeValue = (types, key) => compact(types?.[key] || 0);

const periodKey = (period, key) => {
  if (!period || !key) return null;
  return (period.keys || []).find((item) => item.key === key.key || item.name === key.name) || null;
};

const trendInfo = (history) => {
  if (history.length < 2) return null;
  const first = history[0].total;
  const last = history[history.length - 1].total;
  const delta = last - first;
  const pct = first > 0 ? ((delta / first) * 100) : 0;
  return { delta, pct };
};

const barData = (history) => {
  if (history.length < 2) return [];
  const vals = history.map((p) => p.total);
  const min = Math.min(...vals);
  const max = Math.max(...vals);
  const range = max - min || 1;
  return vals.map((v, i) => ({
    h: ((v - min) / range) * 100,
    last: i === vals.length - 1,
  }));
};

const timeStr = (iso) => {
  if (!iso) return "--:--";
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};

const dateStr = (iso) => {
  if (!iso) return "";
  const d = new Date(iso);
  return `${d.getMonth() + 1}/${d.getDate()}`;
};

// ── Styles ──────────────────────────────────────────────
const container = css`
  position: absolute;
  left: 24px;
  top: 24px;
  width: 300px;
  padding: 18px 20px;
  background: rgba(24, 24, 28, 0.78);
  backdrop-filter: blur(24px) saturate(1.4);
  -webkit-backdrop-filter: blur(24px) saturate(1.4);
  border-radius: 16px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
  color: #e4e4e4;
  box-shadow: 0 2px 32px rgba(0, 0, 0, 0.28), 0 1px 0 rgba(255, 255, 255, 0.04) inset;
`;

const row = css`
  display: flex; align-items: center; justify-content: space-between;
`;

const hdr = css`
  font-size: 10.5px; font-weight: 600;
  color: rgba(255,255,255,0.38);
  text-transform: uppercase; letter-spacing: 0.6px;
`;

const amount = css`
  font-size: 30px; font-weight: 620; color: #fff;
  line-height: 1; font-variant-numeric: tabular-nums;
  letter-spacing: -0.5px; margin: 6px 0 4px;
`;

const sparkline = css`
  display: flex; align-items: flex-end; gap: 2px;
  height: 22px; margin: 10px 0 8px;
`;

const usageGrid = css`
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 6px;
  margin: 12px 0;
`;

const usageCell = css`
  padding: 7px 6px;
  border-radius: 7px;
  background: rgba(255,255,255,0.045);
  border: 1px solid rgba(255,255,255,0.045);
`;

const usageLabel = css`
  font-size: 9.5px;
  color: rgba(255,255,255,0.3);
  text-transform: uppercase;
  font-weight: 650;
`;

const usageTokens = css`
  font-size: 13px;
  color: rgba(255,255,255,0.86);
  font-weight: 650;
  line-height: 1.15;
  margin-top: 3px;
`;

const usageCost = css`
  font-size: 10px;
  color: rgba(255,255,255,0.34);
  margin-top: 2px;
`;

const keysHeader = css`
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin: 2px 0 6px;
`;

const keyList = css`
  display:flex;
  flex-direction:column;
  gap:6px;
  margin-bottom:10px;
`;

const keyRow = css`
  min-width:0;
`;

const keyMain = css`
  display:flex;
  align-items:baseline;
  gap:6px;
  min-width:0;
`;

const keyRank = css`
  color:rgba(255,255,255,0.28);
  font-size:10px;
  width:11px;
  flex:0 0 auto;
`;

const keyName = css`
  color:rgba(255,255,255,0.78);
  font-size:11px;
  font-weight:560;
  overflow:hidden;
  text-overflow:ellipsis;
  white-space:nowrap;
  flex:1;
`;

const keyMetric = css`
  color:rgba(255,255,255,0.62);
  font-size:10.5px;
  font-variant-numeric:tabular-nums;
  flex:0 0 auto;
`;

const keyPeriods = css`
  margin-left:17px;
  margin-top:3px;
  display:grid;
  grid-template-columns: repeat(3, 1fr);
  gap:4px;
`;

const keyPeriod = css`
  color:rgba(255,255,255,0.38);
  font-size:9.5px;
  white-space:nowrap;
`;

const keyTypes = css`
  margin-left:17px;
  margin-top:2px;
  color:rgba(255,255,255,0.28);
  font-size:9.5px;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
`;

const trendRow = css`
  display: flex; align-items: center; gap: 5px;
  font-size: 11.5px; font-weight: 540; margin-bottom: 12px;
`;

const footer = css`
  display: flex; align-items: center; justify-content: space-between;
  padding-top: 10px;
  border-top: 1px solid rgba(255,255,255,0.06);
`;

// ── Additional styles ───────────────────────────────────
const headerRow = css`margin-bottom:4px;`;
const errorDiv = css`color:#ff453a;font-size:12px;text-align:center;padding:8px 0;`;
const loadingDiv = css`font-size:13px;color:rgba(255,255,255,0.2);text-align:center;padding:16px 0;`;
const dateLabel = css`font-size:10px;color:rgba(255,255,255,0.22);`;
const unitLabel = css`font-size:13px;font-weight:500;color:rgba(255,255,255,0.28);margin-left:3px;`;
const subRow = css`font-size:10.5px;color:rgba(255,255,255,0.28);margin-bottom:2px;`;
const trendPct = css`font-size:10.5px;color:rgba(255,255,255,0.25);`;
const trendDays = css`font-size:10px;color:rgba(255,255,255,0.18);margin-left:auto;`;
const statusLabel = css`display:flex;align-items:center;font-size:10.5px;color:rgba(255,255,255,0.4);`;
const timeLabel = css`font-size:10.5px;color:rgba(255,255,255,0.25);`;

const statusDotCss = (ok) => css`
  width:6px;height:6px;border-radius:50%;display:inline-block;margin-right:5px;
  background:${ok ? "#34c759" : "#ff453a"};
  box-shadow:0 0 6px ${ok ? "rgba(52,199,89,0.4)" : "rgba(255,69,58,0.4)"};
`;

// ── Render ──────────────────────────────────────────────
export const render = ({ output, error: commandError }) => {
  const { current, history, usage, updatedAt, error } = parseOutput(output, commandError);

  if (error) {
    return (
      <div className={container}>
        <div className={hdr}>DeepSeek</div>
        <div className={errorDiv}>{error}</div>
      </div>
    );
  }

  if (!current) {
    return (
      <div className={container}>
        <div className={hdr}>DeepSeek</div>
        <div className={loadingDiv}>Loading...</div>
      </div>
    );
  }

  const ti = trendInfo(history);
  const bars = barData(history);
  const deltaAbs = ti ? Math.abs(ti.delta) : 0;
  const deltaSign = ti ? (ti.delta >= 0 ? "+" : "−") : "";
  const deltaColor = ti
    ? ti.delta > 0.001 ? "#34c759" : ti.delta < -0.001 ? "#ff453a" : "rgba(255,255,255,0.3)"
    : "rgba(255,255,255,0.3)";
  const windows = usage?.windows || {};
  const periodCells = [
    ["Today", windows.today],
    ["7D", windows["7d"]],
    ["30D", windows["30d"]],
  ];
  const topKeys = windows["30d"]?.topKeys || [];

  return (
    <div className={container}>
      <div className={[row, headerRow].join(" ")}>
        <span className={hdr}>DeepSeek</span>
        <span className={dateLabel}>{dateStr(current.t)}</span>
      </div>

      <div className={amount}>
        {"¥"}{fmt(current.total)}
        <span className={unitLabel}>CNY</span>
      </div>

      <div className={subRow}>
        <span>Top-up {"¥"}{fmt(current.topped_up)}</span>
        <span style={{ marginLeft: "10px" }}>Grant {"¥"}{fmt(current.granted)}</span>
      </div>

      {usage && (
        <div className={usageGrid}>
          {periodCells.map(([label, period]) => (
            <div className={usageCell} key={label}>
              <div className={usageLabel}>{label}</div>
              <div className={usageTokens}>{compact(period?.tokens || 0)}</div>
              <div className={usageCost}>{fmtCost(period?.cost || 0)}</div>
            </div>
          ))}
        </div>
      )}

      {topKeys.length > 0 && (
        <div>
          <div className={keysHeader}>
            <span className={hdr}>Top Keys · 30D</span>
            <span className={dateLabel}>{usage.latestDate}</span>
          </div>
          <div className={keyList}>
            {topKeys.map((key, i) => (
              <div className={keyRow} key={key.key || key.name}>
                <div className={keyMain}>
                  <span className={keyRank}>{i + 1}</span>
                  <span className={keyName}>{key.name}</span>
                  <span className={keyMetric}>{compact(key.tokens)} · {fmtCost(key.cost)}</span>
                </div>
                <div className={keyPeriods}>
                  {[
                    ["D", periodKey(windows.today, key)],
                    ["7D", periodKey(windows["7d"], key)],
                    ["30D", key],
                  ].map(([label, period]) => (
                    <span className={keyPeriod} key={label}>
                      {label} {compact(period?.tokens || 0)} {fmtCost(period?.cost || 0)}
                    </span>
                  ))}
                </div>
                <div className={keyTypes}>
                  Hit {typeValue(key.types, "input_cache_hit_tokens")} · Miss {typeValue(key.types, "input_cache_miss_tokens")} · Out {typeValue(key.types, "output_tokens")} · Req {compact(key.requests)}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {!usage && bars.length > 1 && (
        <div className={sparkline}>
          {bars.map((b, i) => (
            <div key={i} style={{
              flex: 1,
              height: Math.max(b.h, 3) + "%",
              borderRadius: "1.5px",
              background: b.last ? "rgba(255,255,255,0.55)" : "rgba(255,255,255,0.13)",
              minHeight: "2px",
            }} />
          ))}
        </div>
      )}

      {ti && (
        <div className={trendRow}>
          <span style={{ color: deltaColor, fontSize: "13px", fontWeight: 600 }}>
            {ti.delta >= 0 ? "↑" : "↓"}
          </span>
          <span style={{ color: deltaColor, fontWeight: 540 }}>
            {deltaSign}{"¥"}{fmt(deltaAbs)}
          </span>
          <span className={trendPct}>
            ({ti.pct >= 0 ? "+" : ""}{ti.pct.toFixed(1)}%)
          </span>
          <span className={trendDays}>{history.length}d</span>
        </div>
      )}

      <div className={footer}>
        <span className={statusLabel}>
          <span className={statusDotCss(current.available)} />
          {current.available ? "Available" : "Unavailable"}
        </span>
        <span className={timeLabel}>{timeStr(updatedAt)}</span>
      </div>
    </div>
  );
};
