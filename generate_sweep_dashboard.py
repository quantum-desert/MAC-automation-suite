import json
from pathlib import Path
from statistics import mean
from html import escape


def fmt_num(value, digits=3):
    if value is None:
        return "—"
    return f"{value:.{digits}f}"


def fmt_pct(part, total):
    if not total:
        return "0.0%"
    return f"{(100.0 * part / total):.1f}%"


def js_str(value: str) -> str:
    return json.dumps(value)


def build_dashboard(data: dict) -> str:
    summary = data.get("summary", {})
    rows = data.get("rows", [])
    total_runs = len(rows)

    s1_adv = [r for r in rows if r.get("S1_beatsClassical")]
    s2_adv = [r for r in rows if r.get("S2_beatsClassical")]
    any_adv = [r for r in rows if r.get("anyBeatsClassical")]
    both_adv = [r for r in rows if r.get("bothBeatClassical")]

    s1_indices = [r["runIndex"] for r in s1_adv]
    s2_indices = [r["runIndex"] for r in s2_adv]
    any_indices = [r["runIndex"] for r in any_adv]
    both_indices = [r["runIndex"] for r in both_adv]

    avg_s1_margin = mean(r.get("S1_margin", 0.0) for r in rows) if rows else 0.0
    avg_s2_margin = mean(r.get("S2_margin", 0.0) for r in rows) if rows else 0.0

    labels = [r["runIndex"] for r in rows]
    s1_margin_series = [r.get("S1_margin") for r in rows]
    s2_margin_series = [r.get("S2_margin") for r in rows]
    s1_snre_series = [r.get("S1_SNRe") for r in rows]
    s2_snre_series = [r.get("S2_SNRe") for r in rows]
    s1_classical_series = [r.get("S1_SNR_C") for r in rows]
    s2_classical_series = [r.get("S2_SNR_C") for r in rows]

    table_rows = []
    for r in rows:
        if r.get("S1_beatsClassical") or r.get("S2_beatsClassical"):
            channels = []
            if r.get("S1_beatsClassical"):
                channels.append(f"S1 (+{fmt_num(r.get('S1_margin'))})")
            if r.get("S2_beatsClassical"):
                channels.append(f"S2 (+{fmt_num(r.get('S2_margin'))})")
            table_rows.append(
                f"""
                <tr>
                  <td>{r['runIndex']}</td>
                  <td>{escape(r.get('timestampUtc', ''))}</td>
                  <td>{escape(r.get('flag', ''))}</td>
                  <td>{'<br>'.join(channels)}</td>
                  <td class=\"mono\">{escape(r.get('runDir', ''))}</td>
                </tr>
                """
            )

    summary_cards = [
        ("Last updated (UTC)", data.get("lastUpdatedUtc", "—")),
        ("Total runs", str(summary.get("totalRuns", total_runs))),
        ("Any channel beats classical", f"{summary.get('numAnyBeatsClassical', len(any_adv))} ({fmt_pct(len(any_adv), total_runs)})"),
        ("Both channels beat classical", f"{summary.get('numBothBeatClassical', len(both_adv))} ({fmt_pct(len(both_adv), total_runs)})"),
        ("Best S1 run", f"#{summary.get('bestS1RunIndex', '—')} (margin {fmt_num(summary.get('bestS1Margin'))})"),
        ("Best S2 run", f"#{summary.get('bestS2RunIndex', '—')} (margin {fmt_num(summary.get('bestS2Margin'))})"),
        ("Average S1 margin", fmt_num(avg_s1_margin)),
        ("Average S2 margin", fmt_num(avg_s2_margin)),
    ]

    cards_html = "\n".join(
        f"<div class='card metric'><div class='eyebrow'>{escape(label)}</div><div class='value'>{escape(value)}</div></div>"
        for label, value in summary_cards
    )

    def advantage_list(title: str, indices: list[int], channel_label: str, count: int) -> str:
        return f"""
        <div class="card">
          <div class="section-title">{escape(title)}</div>
          <div class="advantage-meta">{count} / {total_runs} runs ({fmt_pct(count, total_runs)})</div>
          <div class="pill-row">
            {''.join(f"<span class='pill'>{channel_label} #{idx}</span>" for idx in indices) if indices else '<span class="muted">None</span>'}
          </div>
          <div class="index-line mono">[{', '.join(str(i) for i in indices)}]</div>
        </div>
        """

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Sweep SNR Dashboard</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    :root {{
      --bg: #0b1020;
      --panel: #131a2a;
      --panel-2: #1a2338;
      --text: #ecf2ff;
      --muted: #aebbd6;
      --accent: #5eead4;
      --accent-2: #60a5fa;
      --good: #34d399;
      --warn: #fbbf24;
      --border: rgba(255,255,255,0.08);
      --shadow: 0 10px 30px rgba(0,0,0,0.25);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
      background: linear-gradient(180deg, #0b1020, #0f172a 55%, #0b1020);
      color: var(--text);
    }}
    .container {{ max-width: 1400px; margin: 0 auto; padding: 24px; }}
    .hero {{ display: flex; flex-wrap: wrap; gap: 20px; align-items: end; justify-content: space-between; margin-bottom: 22px; }}
    .hero h1 {{ margin: 0; font-size: 2rem; }}
    .hero p {{ margin: 6px 0 0 0; color: var(--muted); }}
    .grid {{ display: grid; gap: 16px; }}
    .metrics {{ grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); margin-bottom: 16px; }}
    .two {{ grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); margin-bottom: 16px; }}
    .card {{
      background: linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0.01));
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 18px;
      box-shadow: var(--shadow);
      backdrop-filter: blur(8px);
    }}
    .metric .eyebrow, .section-title {{ color: var(--muted); font-size: 0.9rem; margin-bottom: 8px; }}
    .metric .value {{ font-size: 1.5rem; font-weight: 700; line-height: 1.25; }}
    .section-title {{ font-weight: 700; letter-spacing: 0.02em; text-transform: uppercase; }}
    .muted {{ color: var(--muted); }}
    .mono {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
    .pill-row {{ display: flex; flex-wrap: wrap; gap: 8px; margin: 12px 0; }}
    .pill {{
      border-radius: 999px;
      padding: 8px 12px;
      background: rgba(94, 234, 212, 0.12);
      border: 1px solid rgba(94, 234, 212, 0.25);
      color: #ccfbf1;
      font-size: 0.95rem;
    }}
    .index-line {{ color: var(--muted); font-size: 0.95rem; word-break: break-word; }}
    .advantage-meta {{ color: var(--muted); margin-bottom: 8px; }}
    .chart-wrap {{ height: 340px; }}
    table {{ width: 100%; border-collapse: collapse; }}
    th, td {{ text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }}
    th {{ color: var(--muted); font-weight: 600; }}
    tr:hover td {{ background: rgba(255,255,255,0.025); }}
    .footer {{ color: var(--muted); font-size: 0.92rem; margin-top: 14px; }}
    a {{ color: var(--accent-2); }}
  </style>
</head>
<body>
  <div class="container">
    <div class="hero">
      <div>
        <h1>Sweep SNR Dashboard</h1>
        <p>Summarizes run-level SNR performance versus classical baselines and explicitly lists every sweep index with positive SNR advantage by channel.</p>
      </div>
      <div class="card" style="min-width: 260px;">
        <div class="section-title">Best overall run</div>
        <div class="metric value">Run #{summary.get('bestAnyRunIndex', '—')}</div>
        <div class="muted">Flag: {escape(str(summary.get('bestAnyFlag', '—')))}</div>
      </div>
    </div>

    <div class="grid metrics">
      {cards_html}
    </div>

    <div class="grid two">
      {advantage_list('S1 sweep indices with SNR advantage', s1_indices, 'S1', len(s1_indices))}
      {advantage_list('S2 sweep indices with SNR advantage', s2_indices, 'S2', len(s2_indices))}
    </div>

    <div class="grid two">
      {advantage_list('Any-channel advantage sweep indices', any_indices, 'RUN', len(any_indices))}
      {advantage_list('Both-channel advantage sweep indices', both_indices, 'RUN', len(both_indices))}
    </div>

    <div class="grid two">
      <div class="card">
        <div class="section-title">Margin vs. classical by run</div>
        <div class="chart-wrap"><canvas id="marginChart"></canvas></div>
      </div>
      <div class="card">
        <div class="section-title">Estimated vs. classical SNR by run</div>
        <div class="chart-wrap"><canvas id="snrChart"></canvas></div>
      </div>
    </div>

    <div class="card">
      <div class="section-title">Runs with positive advantage</div>
      <table>
        <thead>
          <tr>
            <th>Run</th>
            <th>Timestamp (UTC)</th>
            <th>Flag</th>
            <th>Winning channels</th>
            <th>Run directory</th>
          </tr>
        </thead>
        <tbody>
          {''.join(table_rows) if table_rows else '<tr><td colspan="5" class="muted">No positive-margin runs found.</td></tr>'}
        </tbody>
      </table>
      <div class="footer">Generated from the JSON input file.</div>
    </div>
  </div>

  <script>
    const labels = {json.dumps(labels)};
    const s1Margins = {json.dumps(s1_margin_series)};
    const s2Margins = {json.dumps(s2_margin_series)};
    const s1Snre = {json.dumps(s1_snre_series)};
    const s2Snre = {json.dumps(s2_snre_series)};
    const s1Classical = {json.dumps(s1_classical_series)};
    const s2Classical = {json.dumps(s2_classical_series)};

    new Chart(document.getElementById('marginChart'), {{
      type: 'line',
      data: {{
        labels,
        datasets: [
          {{ label: 'S1 margin', data: s1Margins, tension: 0.2, pointRadius: 2, borderWidth: 2 }},
          {{ label: 'S2 margin', data: s2Margins, tension: 0.2, pointRadius: 2, borderWidth: 2 }},
        ]
      }},
      options: {{
        responsive: true,
        maintainAspectRatio: false,
        interaction: {{ mode: 'index', intersect: false }},
        plugins: {{ legend: {{ labels: {{ color: '#ecf2ff' }} }} }},
        scales: {{
          x: {{ ticks: {{ color: '#aebbd6' }}, grid: {{ color: 'rgba(255,255,255,0.06)' }} }},
          y: {{ ticks: {{ color: '#aebbd6' }}, grid: {{ color: 'rgba(255,255,255,0.06)' }}, title: {{ display: true, text: 'Margin', color: '#ecf2ff' }} }}
        }}
      }}
    }});

    new Chart(document.getElementById('snrChart'), {{
      type: 'line',
      data: {{
        labels,
        datasets: [
          {{ label: 'S1 estimated SNR', data: s1Snre, tension: 0.2, pointRadius: 2, borderWidth: 2 }},
          {{ label: 'S1 classical baseline', data: s1Classical, tension: 0, pointRadius: 0, borderDash: [6, 4], borderWidth: 2 }},
          {{ label: 'S2 estimated SNR', data: s2Snre, tension: 0.2, pointRadius: 2, borderWidth: 2 }},
          {{ label: 'S2 classical baseline', data: s2Classical, tension: 0, pointRadius: 0, borderDash: [6, 4], borderWidth: 2 }},
        ]
      }},
      options: {{
        responsive: true,
        maintainAspectRatio: false,
        interaction: {{ mode: 'index', intersect: false }},
        plugins: {{ legend: {{ labels: {{ color: '#ecf2ff' }} }} }},
        scales: {{
          x: {{ ticks: {{ color: '#aebbd6' }}, grid: {{ color: 'rgba(255,255,255,0.06)' }} }},
          y: {{ ticks: {{ color: '#aebbd6' }}, grid: {{ color: 'rgba(255,255,255,0.06)' }}, title: {{ display: true, text: 'SNR', color: '#ecf2ff' }} }}
        }}
      }}
    }});
  </script>
</body>
</html>
"""


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Generate an HTML dashboard from sweep_tracking.json")
    parser.add_argument("input_json", nargs="?", default="sweep_tracking.json", help="Path to input JSON file")
    parser.add_argument("output_html", nargs="?", default="sweep_dashboard.html", help="Path to output HTML file")
    args = parser.parse_args()

    input_path = Path(args.input_json)
    output_path = Path(args.output_html)

    with input_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    html = build_dashboard(data)
    output_path.write_text(html, encoding="utf-8")
    print(f"Wrote dashboard to {output_path.resolve()}")


if __name__ == "__main__":
    main()
