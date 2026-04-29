#!/usr/bin/env python3
import argparse
import datetime as dt
import glob
import json
import math
import os
import time
from collections import Counter, defaultdict
from dataclasses import dataclass

import numpy as np

EPS = 1e-18


@dataclass
class Candidate:
    run_index: int
    channel: str
    mi_bits_per_use: float
    snre: float
    score: float
    margin_vs_classical: float
    advantage_db: float
    method: str
    filter_name: str
    detrend_name: str
    clip_name: str
    threshold_name: str
    invert: bool
    M: int
    phase: int
    lag: int
    n_points: int
    class_balance: float
    homo_file: str
    mod_file: str


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Deterministic MI post-processing optimizer")
    p.add_argument("--root", required=True, help="Directory containing run_xxxxx folders")
    p.add_argument("--report", required=True, help="Path to write markdown optimization report")
    p.add_argument("--json", required=True, help="Path to write machine-readable optimization results")
    p.add_argument(
        "--sweep-tracking-json",
        default="",
        help="Optional sweep_tracking.json used for classical SNR lookup by run/runIndex",
    )
    p.add_argument("--m-values", default="16,18", help="Comma-separated M values to evaluate")
    p.add_argument("--verbose", action="store_true", help="Print per-run progress as optimization executes")
    p.add_argument("--progress-every", type=int, default=10, help="When verbose, print completion summaries every N runs")
    return p.parse_args()


def discover_runs(root: str):
    runs = []
    for entry in sorted(glob.glob(os.path.join(root, "run_*"))):
        if os.path.isdir(entry):
            base = os.path.basename(entry)
            try:
                run_index = int(base.split("_")[-1])
            except ValueError:
                continue
            runs.append((run_index, entry))
    return runs


def read_csv_two_cols(path: str, retries: int = 2, retry_sleep_s: float = 0.2):
    last_err = None
    for attempt in range(1, retries + 1):
        try:
            data = np.loadtxt(path, delimiter=",", skiprows=4)
            return data[:, 0], data[:, 1]
        except OSError as e:
            last_err = e
            # Handle transient cloud/network-backed file stalls.
            if attempt < retries:
                time.sleep(retry_sleep_s * attempt)
                continue
            raise
        except Exception as e:
            last_err = e
            raise
    if last_err is not None:
        raise last_err
    raise RuntimeError(f"Failed to read CSV: {path}")


def find_scope_file(run_dir: str, channel_idx: int):
    pat = os.path.join(run_dir, f"scope_*_{channel_idx}.csv")
    matches = sorted(glob.glob(pat))
    if not matches:
        raise FileNotFoundError(f"Missing scope file for channel {channel_idx} in {run_dir}")
    return matches[0]


def fft_lowpass(x: np.ndarray, fs: float, cutoff_hz: float):
    if cutoff_hz <= 0:
        return np.zeros_like(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(x.size, d=1.0 / fs)
    mask = (f <= cutoff_hz).astype(np.float64)
    return np.fft.irfft(X * mask, n=x.size)


def moving_average(x: np.ndarray, window: int):
    if window <= 1:
        return x.copy()
    kernel = np.ones(window, dtype=np.float64) / float(window)
    return np.convolve(x, kernel, mode="same")


def winsorize(x: np.ndarray, q: float):
    if q <= 0:
        return x.copy()
    lo, hi = np.quantile(x, [q, 1.0 - q])
    return np.clip(x, lo, hi)


def apply_lag(sig: np.ndarray, mod: np.ndarray, lag: int):
    if lag > 0:
        return sig[:-lag], mod[lag:]
    if lag < 0:
        k = -lag
        return sig[k:], mod[:-k]
    return sig, mod


def channel_spec():
    return {
        "S1": {"homo": 2, "mod": 1},
        "S2": {"homo": 3, "mod": 4},
    }


def load_classical_limits(run_dir: str):
    p = os.path.join(run_dir, "processed_summary.json")
    with open(p, "r", encoding="utf-8") as f:
        j = json.load(f)
    return {
        "S1": float(j["S1"]["SNR_C"]),
        "S2": float(j["S2"]["SNR_C"]),
    }


def load_classical_lookup_from_sweep(path: str):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    rows = []
    if isinstance(data, dict) and isinstance(data.get("rows"), list):
        rows = data["rows"]
    elif isinstance(data, list):
        rows = data
    else:
        return {}

    lookup = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        run_idx = row.get("run")
        if run_idx is None:
            run_idx = row.get("runIndex")
        if run_idx is None:
            run_idx = row.get("run_index")
        if run_idx is None:
            continue
        try:
            run_idx = int(run_idx)
        except Exception:
            continue

        s1 = None
        s2 = None
        if "S1_SNR_C" in row:
            s1 = row.get("S1_SNR_C")
        elif isinstance(row.get("S1"), dict):
            s1 = row["S1"].get("SNR_C")

        if "S2_SNR_C" in row:
            s2 = row.get("S2_SNR_C")
        elif isinstance(row.get("S2"), dict):
            s2 = row["S2"].get("SNR_C")

        try:
            if s1 is not None and s2 is not None:
                lookup[run_idx] = {"S1": float(s1), "S2": float(s2)}
        except Exception:
            continue
    return lookup


def compute_snre_asym_xp(xp: np.ndarray, xm: np.ndarray):
    if xp.size < 4 or xm.size < 4:
        return float("nan")
    mu_p = float(np.mean(xp))
    mu_m = float(np.mean(xm))
    sd_p = float(np.std(xp, ddof=1))
    if not np.isfinite(sd_p) or sd_p <= 0:
        return float("nan")
    return (abs(mu_p - mu_m) ** 2) / (4.0 * (sd_p ** 2) + EPS)


def llr_mutual_information(y: np.ndarray, bits: np.ndarray):
    y = y.astype(np.float64, copy=False).reshape(-1)
    b = bits.astype(bool, copy=False).reshape(-1)
    if y.size != b.size:
        return float("nan")

    x1 = y[b]
    x0 = y[~b]
    if x1.size < 4 or x0.size < 4:
        return float("nan")

    mu0 = float(np.mean(x0))
    mu1 = float(np.mean(x1))
    s0 = float(np.std(x0, ddof=0))
    s1 = float(np.std(x1, ddof=0))
    if not np.isfinite(s0) or not np.isfinite(s1) or s0 <= 0 or s1 <= 0:
        return float("nan")

    t = 2.0 * b.astype(np.float64) - 1.0
    L = np.log(s0 / s1) - ((y - mu1) ** 2) / (2.0 * s1 * s1) + ((y - mu0) ** 2) / (2.0 * s0 * s0)
    pen = np.log1p(np.exp(-t * L)) / np.log(2.0)
    I = 1.0 - float(np.mean(pen))
    return float(min(max(I, 0.0), 1.0))


def compute_advantage_db(snre: float, classical: float):
    if snre <= 0 or classical <= 0:
        return float("nan")
    return float(10.0 * math.log10(snre / classical))


def optimize_run_channel(
    run_index: int,
    channel_name: str,
    homo: np.ndarray,
    mod: np.ndarray,
    fs: float,
    classical_limit: float,
    m_values,
):
    filter_defs = [
        ("none", None),
        ("fft_lp_0p6Rb", 0.6),
        ("fft_lp_0p8Rb", 0.8),
    ]
    detrend_defs = [
        ("none", 0),
        ("movmean_2M", 2),
    ]
    clip_defs = [
        ("none", 0.0),
        ("winsor_q0p005", 0.005),
    ]
    threshold_defs = ["mean", "median"]
    invert_defs = [False, True]
    lag_defs = [-1, 0, 1]

    best: Candidate | None = None

    for M in m_values:
        if M < 4:
            continue
        rb = fs / float(M)

        filtered = {}
        for filter_name, ratio in filter_defs:
            if ratio is None:
                filtered[filter_name] = homo
            else:
                filtered[filter_name] = fft_lowpass(homo, fs, ratio * rb)

        for filter_name, base_sig in filtered.items():
            for detrend_name, detrend_mult in detrend_defs:
                if detrend_mult <= 0:
                    detrended = base_sig
                else:
                    detrended = base_sig - moving_average(base_sig, max(3, int(detrend_mult * M)))

                for clip_name, q in clip_defs:
                    sig_proc = winsorize(detrended, q)

                    for lag in lag_defs:
                        sig_lag, mod_lag = apply_lag(sig_proc, mod, lag)
                        n_raw = min(sig_lag.size, mod_lag.size)
                        if n_raw < 8 * M:
                            continue

                        sig_lag = sig_lag[:n_raw]
                        mod_lag = mod_lag[:n_raw]

                        for phase in range(M):
                            hs = sig_lag[phase::M]
                            ms = mod_lag[phase::M]
                            n = min(hs.size, ms.size)
                            if n < 150:
                                continue
                            hs = hs[:n]
                            ms = ms[:n]

                            for threshold_name in threshold_defs:
                                th = float(np.mean(ms)) if threshold_name == "mean" else float(np.median(ms))
                                bits0 = ms > th

                                for invert in invert_defs:
                                    b = (~bits0) if invert else bits0
                                    p = float(np.mean(b))
                                    if p < 0.05 or p > 0.95:
                                        continue

                                    xp = hs[b]
                                    xm = hs[~b]
                                    snre = compute_snre_asym_xp(xp, xm)
                                    if not np.isfinite(snre):
                                        continue

                                    mi = llr_mutual_information(hs, b)
                                    if not np.isfinite(mi):
                                        continue

                                    margin = snre - classical_limit
                                    advantage_db = compute_advantage_db(snre, classical_limit)

                                    cand = Candidate(
                                        run_index=run_index,
                                        channel=channel_name,
                                        mi_bits_per_use=mi,
                                        snre=snre,
                                        score=mi,
                                        margin_vs_classical=margin,
                                        advantage_db=advantage_db,
                                        method=(
                                            f"filter={filter_name}; detrend={detrend_name}; clip={clip_name}; "
                                            f"threshold={threshold_name}; invert={invert}; objective=mi; "
                                            f"M={M}; phase={phase}; lag={lag}"
                                        ),
                                        filter_name=filter_name,
                                        detrend_name=detrend_name,
                                        clip_name=clip_name,
                                        threshold_name=threshold_name,
                                        invert=invert,
                                        M=M,
                                        phase=phase,
                                        lag=lag,
                                        n_points=int(n),
                                        class_balance=p,
                                        homo_file="",
                                        mod_file="",
                                    )

                                    if (best is None) or (cand.score > best.score) or (
                                        cand.score == best.score and cand.snre > best.snre
                                    ):
                                        best = cand

    return best


def fmt_bool(x: bool):
    return "True" if x else "False"


def main():
    args = parse_args()
    root = args.root
    report_path = args.report
    json_path = args.json
    sweep_tracking_json = str(args.sweep_tracking_json or "").strip()
    verbose = bool(args.verbose)
    progress_every = max(1, int(args.progress_every))

    def vprint(msg: str):
        if verbose:
            print(msg, flush=True)

    m_values = [int(x.strip()) for x in args.m_values.split(",") if x.strip()]
    runs = discover_runs(root)
    if not runs:
        raise SystemExit(f"No run_* folders found in {root}")

    classical_lookup = {}
    classical_source = "processed_summary.json"
    if sweep_tracking_json:
        classical_lookup = load_classical_lookup_from_sweep(sweep_tracking_json)
        if classical_lookup:
            classical_source = f"sweep_tracking.json ({sweep_tracking_json})"
        else:
            vprint(
                f"Warning: could not load classical lookup rows from {sweep_tracking_json}. "
                "Falling back to processed_summary.json."
            )

    specs = channel_spec()

    per_run = []
    best_by_channel = {}
    beat_classical = defaultdict(list)
    method_counter = Counter()
    missing_in_sweep = []

    vprint(
        f"Starting MI optimization: root={root}, runs={len(runs)}, "
        f"m_values={m_values}, report={report_path}, json={json_path}"
    )

    for run_num, (run_index, run_dir) in enumerate(runs, start=1):
        t0 = dt.datetime.now(dt.timezone.utc)
        if verbose and run_num <= 5:
            vprint(f"[{run_num}/{len(runs)}] run_{run_index:05d} start")
        try:
            if classical_lookup and run_index in classical_lookup:
                classical = classical_lookup[run_index]
            else:
                classical = load_classical_limits(run_dir)
                if classical_lookup:
                    missing_in_sweep.append(run_index)

            files = {}
            wave = {}
            t_ref = None
            for ci in [1, 2, 3, 4]:
                f = find_scope_file(run_dir, ci)
                t, a = read_csv_two_cols(f)
                files[ci] = f
                wave[ci] = a
                if t_ref is None:
                    t_ref = t
            fs = 1.0 / float(np.mean(np.diff(t_ref)))

            row = {"run_index": run_index}
            ch_summaries = []
            for ch_name, ch_cfg in specs.items():
                h_idx = ch_cfg["homo"]
                m_idx = ch_cfg["mod"]
                best = optimize_run_channel(
                    run_index,
                    ch_name,
                    wave[h_idx],
                    wave[m_idx],
                    fs,
                    classical[ch_name],
                    m_values,
                )
                if best is None:
                    continue
                best.homo_file = os.path.basename(files[h_idx])
                best.mod_file = os.path.basename(files[m_idx])
                row[ch_name] = {
                    "mi_bits_per_use": best.mi_bits_per_use,
                    "snre": best.snre,
                    "classical": classical[ch_name],
                    "margin": best.margin_vs_classical,
                    "advantage_db": best.advantage_db,
                    "method": best.method,
                }
                ch_summaries.append(
                    f"{ch_name}: MI={best.mi_bits_per_use:.6g}, SNRe={best.snre:.6g}, "
                    f"SNR_C={classical[ch_name]:.6g}, margin={best.margin_vs_classical:+.6g}"
                )
                method_counter[(best.filter_name, best.detrend_name, best.clip_name, best.threshold_name, best.invert, best.M, best.lag)] += 1

                if ch_name not in best_by_channel or best.mi_bits_per_use > best_by_channel[ch_name].mi_bits_per_use:
                    best_by_channel[ch_name] = best

                if best.margin_vs_classical > 0:
                    beat_classical[ch_name].append(run_index)

            per_run.append(row)
            if verbose and (run_num % progress_every == 0 or run_num == len(runs)):
                elapsed = (dt.datetime.now(dt.timezone.utc) - t0).total_seconds()
                ch_msg = " | ".join(ch_summaries) if ch_summaries else "no valid channel candidates"
                vprint(f"[{run_num}/{len(runs)}] run_{run_index:05d} done in {elapsed:.2f}s | {ch_msg}")
        except Exception as e:
            per_run.append({"run_index": run_index, "error": str(e)})
            vprint(f"[{run_num}/{len(runs)}] run_{run_index:05d} ERROR: {e}")

    ts = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    top_method = None
    if method_counter:
        (k, count) = method_counter.most_common(1)[0]
        top_method = {
            "signature": {
                "filter": k[0],
                "detrend": k[1],
                "clip": k[2],
                "threshold": k[3],
                "invert": k[4],
                "M": k[5],
                "lag": k[6],
            },
            "count": count,
        }

    result = {
        "generated_utc": ts,
        "root": root,
        "num_runs": len(runs),
        "m_values": m_values,
        "classical_source": classical_source,
        "missing_in_sweep_tracking": sorted(set(missing_in_sweep)),
        "best_by_channel": {
            ch: {
                "run_index": c.run_index,
                "mi_bits_per_use": c.mi_bits_per_use,
                "snre": c.snre,
                "margin_vs_classical": c.margin_vs_classical,
                "advantage_db": c.advantage_db,
                "method": c.method,
                "filter": c.filter_name,
                "detrend": c.detrend_name,
                "clip": c.clip_name,
                "threshold": c.threshold_name,
                "invert": c.invert,
                "M": c.M,
                "phase": c.phase,
                "lag": c.lag,
                "n_points": c.n_points,
                "class_balance": c.class_balance,
                "homo_file": c.homo_file,
                "mod_file": c.mod_file,
            }
            for ch, c in best_by_channel.items()
        },
        "beat_classical_indices": {ch: sorted(v) for ch, v in beat_classical.items()},
        "top_method": top_method,
        "per_run": per_run,
    }

    os.makedirs(os.path.dirname(json_path), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    vprint(f"Wrote JSON: {json_path}")

    lines = []
    lines.append("# MI Post-Processing Optimization Report")
    lines.append("")
    lines.append(f"Generated (UTC): {ts}")
    lines.append(f"Runs processed: {len(runs)}")
    lines.append(f"Classical reference source: {classical_source}")
    if missing_in_sweep:
        lines.append(f"Runs missing in sweep-tracking SNR_C (fallback to processed_summary): {len(set(missing_in_sweep))}")
    lines.append("")
    lines.append("## Best MI-Optimized Result by Channel")
    lines.append("")
    lines.append("| Channel | Best Run Index | Max MI (bits/use) | Extracted SNRe | Classical SNR_C (same run) | SNR Margin | Advantage in dB | Homodyne File | Mod File |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---|---|")
    for ch in ["S1", "S2"]:
        b = best_by_channel.get(ch)
        if not b:
            lines.append(f"| {ch} | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")
            continue
        classical = b.snre - b.margin_vs_classical
        adv_txt = f"{b.advantage_db:+.6f}" if np.isfinite(b.advantage_db) else "n/a"
        lines.append(
            f"| {ch} | {b.run_index} | {b.mi_bits_per_use:.6f} | {b.snre:.6f} | {classical:.6f} | {b.margin_vs_classical:+.6f} | {adv_txt} | {b.homo_file} | {b.mod_file} |"
        )

    lines.append("")
    lines.append("## Classical-Limit Flags (by SNRe margin)")
    lines.append("")
    for ch in ["S1", "S2"]:
        flagged = sorted(beat_classical.get(ch, []))
        if flagged:
            lines.append(f"- {ch}: beats classical limit at run indices {', '.join(str(x) for x in flagged)}")
        else:
            lines.append(f"- {ch}: no run exceeded classical SNR_C under MI-optimized sweep")

    lines.append("")
    lines.append("## Best Method Settings (Per Channel Winner)")
    lines.append("")
    for ch in ["S1", "S2"]:
        b = best_by_channel.get(ch)
        if not b:
            continue
        lines.append(f"### {ch}")
        lines.append(f"- run index: {b.run_index}")
        lines.append(f"- objective MI (bits/use): `{b.mi_bits_per_use:.6f}`")
        lines.append(f"- extracted SNRe: `{b.snre:.6f}`")
        lines.append(f"- SNR margin vs classical: `{b.margin_vs_classical:+.6f}`")
        lines.append(f"- advantage in dB: `{b.advantage_db:+.6f}`")
        lines.append(f"- filter: `{b.filter_name}`")
        lines.append(f"- detrend: `{b.detrend_name}`")
        lines.append(f"- clip: `{b.clip_name}`")
        lines.append(f"- threshold: `{b.threshold_name}`")
        lines.append(f"- modulation invert: `{fmt_bool(b.invert)}`")
        lines.append(f"- samples/symbol M: `{b.M}`")
        lines.append(f"- best phase: `{b.phase}`")
        lines.append(f"- best modulation lag (samples): `{b.lag}`")
        lines.append(f"- downsampled points: `{b.n_points}`")
        lines.append(f"- class balance: `{b.class_balance:.3f}`")
        lines.append("")

    lines.append("## Most Successful Optimization Method")
    lines.append("")
    if top_method:
        s = top_method["signature"]
        lines.append(
            "The most frequently selected winner across run-channel MI optimizations used "
            f"`{s['filter']}` filtering, `{s['detrend']}` detrending, `{s['clip']}` clipping, "
            f"`{s['threshold']}` thresholding, inversion=`{fmt_bool(bool(s['invert']))}`, "
            f"`M={s['M']}`, and lag=`{s['lag']}`. It appeared in {top_method['count']} winning selections."
        )
    else:
        lines.append("No valid winning method could be determined.")

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- Optimization objective was MI (`I_soft`) from Gaussian LLR decoding per channel.")
    lines.append("- SNRe and classical margin were computed and reported for the same MI-optimized settings.")
    lines.append("- Channel-specific classical `SNR_C` was pulled per run and per channel from sweep tracking when available.")
    lines.append("- `Advantage in dB` is computed as `10*log10(SNRe/SNR_C)`.")
    lines.append("- Channel mapping used: S1 homodyne `scope_*_2.csv` with modulation `scope_*_1.csv`; S2 homodyne `scope_*_3.csv` with modulation `scope_*_4.csv`.")

    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    vprint(f"Wrote report: {report_path}")
    vprint("MI optimization complete.")


if __name__ == "__main__":
    main()
