# Grafana Dashboard JSON — Field-by-Field Explanation

This document explains every field in `dashboard-learning-template.json`.  
Import the JSON into Grafana via **Dashboards → Import → Upload JSON file** to see the live dashboard.

---

## Table of Contents

1. [Dashboard-Level Fields](#1-dashboard-level-fields)
2. [Grid System (gridPos)](#2-grid-system-gridpos)
3. [Panel Types Overview](#3-panel-types-overview)
4. [Panel 1 — Text (markdown header)](#4-panel-1--text-markdown-header)
5. [Panel 2 — Stat: Server Up/Down](#5-panel-2--stat-server-updown)
6. [Panel 3 — Stat: Current CPU %](#6-panel-3--stat-current-cpu-)
7. [Panel 4 — Stat: Log Volume (Loki metric query)](#7-panel-4--stat-log-volume-loki-metric-query)
8. [Panel 5 — Timeseries: CPU Over Time](#8-panel-5--timeseries-cpu-over-time)
9. [Panel 6 — Timeseries: Log Volume as Bars](#9-panel-6--timeseries-log-volume-as-bars)
10. [Panel 7 — Logs: Raw Log Lines](#10-panel-7--logs-raw-log-lines)
11. [fieldConfig in Depth](#11-fieldconfig-in-depth)
12. [targets (Queries) in Depth](#12-targets-queries-in-depth)
13. [Common Mistakes](#13-common-mistakes)

---

## 1. Dashboard-Level Fields

These fields sit at the root of the JSON object, outside the `panels` array.

```json
{
  "id": null,
  "uid": "dashboard-learning-template",
  "title": "Dashboard Learning Template",
  "schemaVersion": 38,
  "version": 1,
  "editable": true,
  "liveNow": false,
  "graphTooltip": 1,
  "timezone": "browser",
  "refresh": "30s",
  "time": { "from": "now-1h", "to": "now" },
  "timepicker": {},
  "tags": ["learning", "template"],
  "links": [],
  "annotations": { "list": [] }
}
```

| Field | Type | What it does |
|---|---|---|
| `id` | number \| null | Internal Grafana database ID. Always set to `null` when exporting to share — Grafana assigns a new ID on import. |
| `uid` | string | Stable, human-readable identifier. Used in URLs: `/d/<uid>/title`. Must be unique across Grafana. Use lowercase kebab-case. |
| `title` | string | The name shown in the Grafana dashboard list and browser tab. |
| `schemaVersion` | number | The Grafana JSON schema version. `38` works with Grafana 9.x and 10.x. Do not change this unless you know what you're doing. |
| `version` | number | Dashboard revision counter. Grafana increments this every time you save. Set to `1` for new dashboards. |
| `editable` | boolean | Whether users can edit panels from the UI. Set `false` for "locked" production dashboards. |
| `liveNow` | boolean | When `true`, the dashboard clock ticks in real time every second. Useful for log dashboards. Set `false` for metrics (Grafana auto-refreshes on the `refresh` interval instead). |
| `graphTooltip` | 0 \| 1 \| 2 | `0` = default tooltip (one panel at a time). `1` = shared crosshair (hover shows vertical line across all panels). `2` = shared tooltip (shows all panel values at cursor position). |
| `timezone` | string | `"browser"` uses the viewer's local timezone. Can also be a IANA timezone like `"UTC"` or `"America/New_York"`. |
| `refresh` | string | Auto-refresh interval. Valid values: `"5s"`, `"10s"`, `"30s"`, `"1m"`, `"5m"`, `"15m"`, `"30m"`, `"1h"`, `"2h"`, `"1d"`. Empty string `""` disables auto-refresh. |
| `time` | object | The default time range shown when you open the dashboard. `"now-1h"` means "last 1 hour". |
| `timepicker` | object | Controls the time picker widget. Empty `{}` uses defaults. |
| `tags` | string[] | Labels for organising dashboards in the Grafana search/browse UI. |
| `links` | array | Adds navigation links in the top-right corner of the dashboard. Empty array = none. |
| `annotations` | object | Overlays events on timeseries panels (e.g. deployments, alert firings). Empty list = none. |

---

## 2. Grid System (gridPos)

Every panel has a `gridPos` object that controls where it sits on the canvas.

```json
"gridPos": { "x": 0, "y": 3, "w": 12, "h": 8 }
```

| Field | Unit | Max | What it means |
|---|---|---|---|
| `x` | grid columns | 24 | Left edge of the panel. The full width of a dashboard is **24 columns**. |
| `y` | grid rows | unlimited | Top edge of the panel. Panels stack downward as `y` increases. |
| `w` | grid columns | 24 | Panel width. `24` = full width. `12` = half width. `6` = quarter width. |
| `h` | grid rows | unlimited | Panel height. Each unit is roughly 30 px. `4` = short stat card. `8` = normal chart. `12` = tall log panel. |

**Full-width layout example:**
```
x=0  w=24  → one panel spanning the full row
```

**Two-column layout example:**
```
x=0  w=12  → left panel
x=12 w=12  → right panel (same y value)
```

**Rule:** No two panels should overlap. If they do, Grafana will push them down automatically.

---

## 3. Panel Types Overview

Every panel has a `"type"` field. This dashboard uses four:

| `type` value | What it renders | Needs `targets`? | Typical `fieldConfig`? |
|---|---|---|---|
| `"text"` | Static Markdown or HTML | No | No |
| `"stat"` | Single big number with colour | Yes | Yes — thresholds/mappings |
| `"timeseries"` | Line or bar chart over time | Yes | Yes — custom draw style |
| `"logs"` | Raw log lines (Loki only) | Yes | Minimal |

Other types not shown here: `"gauge"`, `"bargauge"`, `"table"`, `"piechart"`, `"heatmap"`, `"histogram"`.

---

## 4. Panel 1 — Text (markdown header)

```json
{
  "id": 1,
  "type": "text",
  "title": "What is This Dashboard?",
  "gridPos": { "x": 0, "y": 0, "w": 24, "h": 3 },
  "datasource": null,
  "options": {
    "mode": "markdown",
    "content": "# Heading\n\nParagraph text here."
  }
}
```

| Field | Explanation |
|---|---|
| `type: "text"` | Renders static content — no live data. |
| `datasource: null` | No data source needed. Grafana accepts `null` here. |
| `options.mode` | `"markdown"` renders Markdown. Can also be `"html"` for raw HTML. |
| `options.content` | The actual text. Use `\n` for newlines. Markdown tables, headings, bold, italic all work. |

**When to use it:** Dashboard description, instructions, links to runbooks, region/section headers.

---

## 5. Panel 2 — Stat: Server Up/Down

```json
{
  "id": 2,
  "type": "stat",
  "title": "App Server — Up or Down",
  "gridPos": { "x": 0, "y": 3, "w": 6, "h": 4 },
  "datasource": { "type": "prometheus", "uid": "Prometheus" },
  "targets": [
    {
      "expr": "up{job=\"node_exporter\"}",
      "instant": true,
      "refId": "A"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "short",
      "mappings": [
        {
          "type": "value",
          "options": {
            "0": { "text": "DOWN", "color": "red" },
            "1": { "text": "UP",   "color": "green" }
          }
        }
      ],
      "thresholds": {
        "mode": "absolute",
        "steps": [
          { "value": null, "color": "red"   },
          { "value": 1,    "color": "green" }
        ]
      },
      "color": { "mode": "thresholds" }
    }
  },
  "options": {
    "colorMode": "background",
    "graphMode": "none",
    "reduceOptions": { "calcs": ["lastNotNull"] }
  }
}
```

### datasource

```json
"datasource": { "type": "prometheus", "uid": "Prometheus" }
```

- `type`: the plugin type — `"prometheus"` or `"loki"`.
- `uid`: the provisioned datasource UID from Grafana. In this project, Prometheus is provisioned with `uid: "Prometheus"` and Loki with `uid: "Loki"` (see `provisioning/datasources/`).

### targets[0].expr

```
up{job="node_exporter"}
```

- `up` is a built-in Prometheus metric. It returns `1` if the scrape target is reachable, `0` if not.
- `{job="node_exporter"}` filters to only the app server's Node Exporter target.

### targets[0].instant

`true` means "give me the most recent single value", not a range of data points over time. Use `instant: true` for stat panels. Use `instant: false` (or omit it) for timeseries panels.

### fieldConfig.defaults.mappings

Value mappings transform raw numbers into human-readable text with colour:

```json
"mappings": [{
  "type": "value",
  "options": {
    "0": { "text": "DOWN", "color": "red"   },
    "1": { "text": "UP",   "color": "green" }
  }
}]
```

- `type: "value"` maps exact values.
- Other mapping types: `"range"` (a range of numbers), `"regex"` (pattern match on string values), `"special"` (null, NaN, infinity).

### fieldConfig.defaults.thresholds

```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    { "value": null, "color": "red"   },
    { "value": 1,    "color": "green" }
  ]
}
```

- `mode: "absolute"` compares the raw value. `"percentage"` compares relative to min/max.
- Steps are ordered. The first step always has `value: null` (meaning "everything below the first real threshold").
- This says: below 1 → red, at or above 1 → green.

### options.colorMode

| Value | Effect |
|---|---|
| `"background"` | The entire panel card changes colour |
| `"value"` | Only the number text changes colour |
| `"none"` | No colour applied |

### options.graphMode

| Value | Effect |
|---|---|
| `"none"` | Just the number, no sparkline |
| `"area"` | Shows a small sparkline area chart below the number |

### options.reduceOptions.calcs

Controls which calculation is shown when the query returns multiple data points:

| Value | Meaning |
|---|---|
| `"lastNotNull"` | Most recent non-null value — best for "current state" panels |
| `"mean"` | Average over the time range |
| `"max"` | Maximum value in the time range |
| `"min"` | Minimum value in the time range |
| `"sum"` | Total sum |

---

## 6. Panel 3 — Stat: Current CPU %

```json
"expr": "100 - (avg by(instance)(irate(node_cpu_seconds_total{mode=\"idle\",job=\"node_exporter\"}[5m])) * 100)"
```

Breaking down the PromQL:

| Part | Meaning |
|---|---|
| `node_cpu_seconds_total` | Counter: cumulative CPU time spent in each mode (idle, user, system, iowait…) |
| `{mode="idle", job="node_exporter"}` | Filter: only the "idle" mode, only from the app server exporter |
| `irate(...[5m])` | Instant rate — calculates the per-second rate using the last two samples within a 5-minute window. Use `irate` for fast-changing counters, `rate` for slower ones. |
| `avg by(instance)(...)` | Average across all CPU cores (multi-core servers expose one time series per core) |
| `* 100` | Convert fraction to percentage |
| `100 - (...)` | Invert: idle % → usage % |

This panel also demonstrates `"unit": "percent"` with `"min": 0, "max": 100` in `fieldConfig.defaults`:

```json
"fieldConfig": {
  "defaults": {
    "unit": "percent",
    "min": 0,
    "max": 100,
    ...
  }
}
```

The `unit` field controls how Grafana formats the displayed number. Common units:

| Unit string | Display example |
|---|---|
| `"percent"` | `72.3%` |
| `"short"` | `72.3` (auto SI suffix) |
| `"decbytes"` | `512 MB` |
| `"Bps"` | `1.2 MB/s` |
| `"s"` | `3.4 s` |
| `"ms"` | `340 ms` |
| `"none"` | raw number, no formatting |

---

## 7. Panel 4 — Stat: Log Volume (Loki metric query)

```json
"datasource": { "type": "loki", "uid": "Loki" },
"targets": [{
  "expr": "sum(count_over_time({job=\"bmi-backend\"}[5m]))",
  "instant": true,
  "refId": "A"
}]
```

Loki supports two query types:

| Query type | Returns | Example |
|---|---|---|
| **Log query** | Raw log lines | `{job="bmi-backend"}` |
| **Metric query** | Numeric time series | `count_over_time({job="bmi-backend"}[5m])` |

`count_over_time({...}[5m])` counts the number of log lines in each 5-minute bucket. This turns log data into a number that can be shown in a stat or timeseries panel.

`sum(...)` aggregates across all label combinations (in case the same job has multiple streams).

---

## 8. Panel 5 — Timeseries: CPU Over Time

```json
{
  "id": 5,
  "type": "timeseries",
  ...
  "targets": [
    { "expr": "...", "legendFormat": "CPU usage %", "refId": "A" },
    { "expr": "...", "legendFormat": "IO wait %",   "refId": "B" }
  ]
}
```

### Multiple targets = multiple series

Each entry in `targets` produces one line on the chart. `refId` must be unique within the panel (`"A"`, `"B"`, `"C"`...).

### legendFormat

Controls the label shown in the legend. You can include Prometheus label values using `{{label_name}}`:

```
"legendFormat": "CPU on {{instance}}"
```

If left empty, Grafana auto-generates a label from the metric name and labels.

### fieldConfig.defaults.custom — drawing style

The `custom` block inside `fieldConfig.defaults` controls how the line/bar is drawn:

```json
"custom": {
  "drawStyle": "line",
  "lineWidth": 2,
  "fillOpacity": 15,
  "showPoints": "never",
  "spanNulls": false,
  "lineInterpolation": "linear"
}
```

| Field | Values | Effect |
|---|---|---|
| `drawStyle` | `"line"`, `"bars"`, `"points"` | Shape of the series |
| `lineWidth` | number (px) | Thickness of the line |
| `fillOpacity` | 0–100 | How opaque the area fill under the line is |
| `showPoints` | `"never"`, `"always"`, `"auto"` | Whether to draw dots at each data point |
| `spanNulls` | `false`, `true`, number (ms) | Whether to connect a line across gaps in data |
| `lineInterpolation` | `"linear"`, `"smooth"`, `"stepBefore"`, `"stepAfter"` | How the line curves between points |

### options.legend

```json
"legend": {
  "displayMode": "table",
  "placement": "bottom",
  "showLegend": true,
  "calcs": ["lastNotNull", "max", "mean"]
}
```

| Field | Effect |
|---|---|
| `displayMode: "table"` | Shows a table with calculated columns. `"list"` shows a simple list. `"hidden"` hides it. |
| `placement: "bottom"` | Legend below the graph. `"right"` puts it on the right side. |
| `calcs` | Extra columns in the table: last value, max, mean, min, sum, etc. |

### options.tooltip

```json
"tooltip": { "mode": "multi", "sort": "none" }
```

- `"single"` — hover shows only the nearest series.
- `"multi"` — hover shows all series values at that timestamp.

---

## 9. Panel 6 — Timeseries: Log Volume as Bars

This panel uses the same `timeseries` type but switches to bars:

```json
"custom": {
  "drawStyle": "bars",
  "fillOpacity": 100,
  "stacking": { "group": "A", "mode": "normal" },
  "axisLabel": "log lines / min"
}
```

`stacking.mode: "normal"` stacks multiple series on top of each other instead of overlapping. Useful for volume charts where you want to see the total at a glance.

The Loki query uses a `[1m]` range vector to get per-minute buckets, which aligns with the bar width:

```
sum by(job) (count_over_time({job="bmi-backend"}[1m]))
```

---

## 10. Panel 7 — Logs: Raw Log Lines

```json
{
  "id": 7,
  "type": "logs",
  "targets": [{
    "expr": "{job=\"bmi-backend\"}",
    "refId": "A"
  }],
  "options": {
    "showTime": true,
    "showLabels": false,
    "showCommonLabels": false,
    "wrapLogMessage": false,
    "prettifyLogMessage": false,
    "enableLogDetails": true,
    "sortOrder": "Descending",
    "dedupStrategy": "none"
  }
}
```

The `logs` type only works with **Loki** as the data source. `fieldConfig` is not used — the display is fully controlled by `options`:

| Option | Values | Effect |
|---|---|---|
| `showTime` | bool | Show timestamp column |
| `showLabels` | bool | Show all Loki stream labels on each line |
| `showCommonLabels` | bool | Show labels that are identical across all lines at the top |
| `wrapLogMessage` | bool | Wrap long lines or let them scroll horizontally |
| `prettifyLogMessage` | bool | Auto-format JSON log lines with indentation |
| `enableLogDetails` | bool | Allow clicking a log line to expand its full details |
| `sortOrder` | `"Descending"`, `"Ascending"` | Newest first or oldest first |
| `dedupStrategy` | `"none"`, `"exact"`, `"numbers"`, `"signature"` | Collapse consecutive identical lines |

### LogQL — the Loki query language

| Query | Meaning |
|---|---|
| `{job="bmi-backend"}` | All log lines from the `bmi-backend` job |
| `{job="bmi-backend"} \|= "error"` | Lines containing "error" (case-sensitive) |
| `{job="bmi-backend"} \|~ "(?i)error"` | Lines matching regex (case-insensitive) |
| `{job="bmi-backend"} != "health"` | Lines NOT containing "health" |
| `{job=~"nginx.*"}` | Jobs matching a regex pattern |
| `{server="app-server", job="bmi-backend"}` | Multiple label filters (AND) |

---

## 11. fieldConfig in Depth

`fieldConfig` applies formatting to the data returned by `targets`. It has two sections:

```json
"fieldConfig": {
  "defaults": { ... },
  "overrides": [ ... ]
}
```

- `defaults` — applied to every series/field in the panel.
- `overrides` — applied only to specific series, overriding `defaults`.

### overrides example — colour one specific series red

```json
"overrides": [
  {
    "matcher": { "id": "byName", "options": "IO wait %" },
    "properties": [
      { "id": "color", "value": { "mode": "fixed", "fixedColor": "orange" } }
    ]
  }
]
```

`matcher.id` can be:
- `"byName"` — by the series legend name
- `"byRegexp"` — by regex match on legend name
- `"byFrameRefID"` — by the `refId` (`"A"`, `"B"`, etc.)
- `"byType"` — by data type (number, string, time)

---

## 12. targets (Queries) in Depth

Every panel has a `targets` array. Each target is one query.

### Prometheus target

```json
{
  "datasource": { "type": "prometheus", "uid": "Prometheus" },
  "expr": "node_load1{job=\"node_exporter\"}",
  "instant": false,
  "legendFormat": "1m load on {{instance}}",
  "refId": "A"
}
```

| Field | Explanation |
|---|---|
| `expr` | PromQL expression. Escape double quotes inside JSON strings. |
| `instant` | `true` = single point query (for stat panels). `false` = range query over the dashboard time window (for timeseries panels). |
| `legendFormat` | Series name shown in the legend. `{{label}}` interpolates a Prometheus label value. |
| `refId` | Unique query identifier within the panel. Used by `overrides` matchers. |
| `interval` | Override scrape interval for this query (e.g. `"1m"`). Omit to use dashboard default. |

### Loki target

```json
{
  "datasource": { "type": "loki", "uid": "Loki" },
  "expr": "{job=\"bmi-backend\"}",
  "refId": "A"
}
```

- For `logs` panels: use a log query `{...}` — returns raw lines, no aggregation.
- For `stat` or `timeseries` panels: use a metric query `count_over_time({...}[5m])` — returns numbers.

---

## 13. Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| `uid` collision | Dashboard silently overwrites another | Use a unique string like `"my-team-cpu-dashboard"` |
| `instant: true` on a timeseries panel | Empty chart or "no data" | Remove `instant` or set it to `false` |
| `instant: false` on a stat panel | Shows a list of values instead of one | Set `instant: true` and set `reduceOptions.calcs` |
| Wrong datasource `uid` | "Data source not found" error | Check Grafana → Configuration → Data sources for the exact UID |
| `gridPos` panels overlap | Panels stack on each other | Make sure `x + w` of panel A ≤ `x` of panel B on the same row |
| Missing `refId` | Grafana may error or ignore the query | Always include `"refId": "A"` on every target |
| Escaped quotes wrong | JSON parse error on import | In JSON, use `\"` inside strings: `"expr": "up{job=\"node_exporter\"}"` |
| `thresholds.steps[0].value` not null | First colour never applies | First step must always be `{ "value": null, "color": "..." }` |

---

## Quick Reference — Build a New Panel

```
1. Pick a type:    "stat" | "timeseries" | "logs" | "text" | "piechart" | "table"
2. Set gridPos:    x, y (position) and w, h (size) — max width = 24
3. Set datasource: { "type": "prometheus"|"loki", "uid": "Prometheus"|"Loki" }
4. Write targets:  one entry per series, unique refId per entry
5. Set fieldConfig.defaults:
     - unit (how to format the number)
     - thresholds (what colour at what value)
     - custom (line style for timeseries)
6. Set options:
     - reduceOptions.calcs for stat panels
     - legend and tooltip for timeseries panels
     - showTime, sortOrder, etc. for log panels
```
