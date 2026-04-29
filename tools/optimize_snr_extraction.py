#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import glob
import json
import math
import os
from collections import Counter, defaultdict
from dataclasses import dataclass

import numpy as np


EPS = 1e-18


@dataclass
class Candidate:
    run_index: int
    run_dir: str
    run_relpath: str
    channel: str
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
    metric: str
    M: int
    phase: int
    lag: int
    n_points: int
    class_balance: float
    homo_file: str
    mod_file: str


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Deterministic SNR post-processing optimizer")
    p.add_argument("--root", required=True, help="Directory containing run_xxxxx folders")
    p.add_argument(
        "--recursive-runs",
        action="store_true",
        help="Recursively search under --root for run_xxxxx folders",
    )
    p.add_argument("--report", required=True, help="Path to write markdown optimization report")
    p.add_argument("--json", required=True, help="Path to write machine-readable optimization results")
    p.add_argument(
        "--sweep-tracking-json",
        default="",
        help="Optional sweep_tracking.json used for classical SNR lookup by run/runIndex",
    )
    p.add_argument("--m-values", default="16,18", help="Comma-separated M values to evaluate")
    p.add_argument(
        "--dynamic-m",
        action="store_true",
        help="Use per-channel M computed from Fs and bit rate (M=round(Fs/Rb)) instead of fixed --m-values",
    )
    p.add_argument("--rb-s1", type=float, default=16000.0, help="Bit rate (Hz) for S1 when --dynamic-m is enabled")
    p.add_argument("--rb-s2", type=float, default=16000.0, help="Bit rate (Hz) for S2 when --dynamic-m is enabled")
    p.add_argument(
        "--fallback-classical-from-run",
        type=int,
        default=-1,
        help="If >=0, use this run's SNR_C values whenever a run is missing processed_summary.json",
    )
    p.add_argument(
        "--phase-multiplier",
        type=int,
        default=1,
        help="Evaluate start phase over phase_multiplier*M candidates",
    )
    p.add_argument(
        "--lag-range",
        type=int,
        default=1,
        help="Evaluate integer lags from -lag_range to +lag_range (inclusive)",
    )
    p.add_argument("--verbose", action="store_true", help="Print per-run progress as optimization executes")
    p.add_argument("--progress-every", type=int, default=1, help="When verbose, print completion summaries every N runs")
    p.add_argument(
        "--run-index-file",
        default="",
        help="Optional path with run indices to process (comma/space/newline separated).",
    )
    p.add_argument(
        "--clip-mode",
        default="all",
        choices=["all", "none-only", "winsor-only"],
        help="Clip sweep mode: all clips, no-clip only, or winsor-only.",
    )
    p.add_argument(
        "--disallow-brickwall-filters",
        action="store_true",
        help="Exclude FFT brick-wall filters from the method sweep.",
    )
    return p.parse_args()


def discover_runs(root: str, recursive: bool = False):
    runs = []
    entries = []
    if recursive:
        patterns = [
            os.path.join(root, "**", "run_*"),
            os.path.join(root, "**", "*_run_*"),
        ]
        for pattern in patterns:
            entries.extend(glob.glob(pattern, recursive=True))
    else:
        patterns = [
            os.path.join(root, "run_*"),
            os.path.join(root, "*_run_*"),
        ]
        for pattern in patterns:
            entries.extend(glob.glob(pattern))

    entries = sorted(set(entries))

    seen = set()
    for entry in entries:
        if not os.path.isdir(entry):
            continue
        norm = os.path.realpath(entry)
        if norm in seen:
            continue
        seen.add(norm)
        base = os.path.basename(entry)
        try:
            run_index = int(base.split("_")[-1])
        except ValueError:
            continue
        runs.append((run_index, entry))
    return runs


def load_run_index_filter(path: str):
    txt = open(path, "r", encoding="utf-8").read()
    toks = txt.replace(",", " ").split()
    out = set()
    for t in toks:
        try:
            out.add(int(t))
        except Exception:
            continue
    return out


def read_csv_two_cols(path: str):
    data = np.loadtxt(path, delimiter=",", skiprows=4)
    return data[:, 0], data[:, 1]


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


def infer_m_candidates_from_mod(mod: np.ndarray, fs: float, fallback_m_values):
    bits_raw = mod > float(np.mean(mod))
    bits = moving_average(bits_raw.astype(np.float64), 5) > 0.5
    transitions = np.flatnonzero(np.diff(bits.astype(np.int8)) != 0) + 1

    max_m = min(4096, max(32, int(mod.size // 200)))
    m0 = None
    if transitions.size >= 8:
        intervals = np.diff(transitions)
        intervals = intervals[intervals >= 4]
        if intervals.size >= 4:
            q35 = float(np.quantile(intervals, 0.35))
            short = intervals[intervals <= q35]
            if short.size >= 3:
                m0 = int(round(float(np.median(short))))
            else:
                m0 = int(round(float(np.median(intervals))))

    if m0 is None or m0 < 4:
        x = mod - float(np.mean(mod))
        X = np.abs(np.fft.rfft(x))
        f = np.fft.rfftfreq(x.size, d=1.0 / fs)
        if X.size > 4:
            lo = max(1.0, fs / 50000.0)
            hi = fs / 8.0
            band = np.flatnonzero((f >= lo) & (f <= hi))
            if band.size > 0:
                peak_i = band[int(np.argmax(X[band]))]
                f_peak = float(f[peak_i])
                if f_peak > 0:
                    m0 = int(round(fs / f_peak))

    if m0 is None or m0 < 4:
        return list(sorted(set(int(m) for m in fallback_m_values if int(m) >= 4)))

    m0 = max(4, min(int(m0), max_m))
    deltas = [0, -1, 1, -2, 2, -4, 4, -8, 8]
    pct = max(1, int(round(0.05 * m0)))
    deltas += [-pct, pct]
    candidates = set()
    for d in deltas:
        m = int(m0 + d)
        if 4 <= m <= max_m:
            candidates.add(m)
    if 4 <= m0 // 2 <= max_m:
        candidates.add(int(round(m0 / 2.0)))
    if 4 <= int(round(2.0 * m0)) <= max_m:
        candidates.add(int(round(2.0 * m0)))

    out = sorted(candidates)
    if not out:
        return list(sorted(set(int(m) for m in fallback_m_values if 4 <= int(m) <= max_m)))
    if len(out) > 17:
        center = sorted(out, key=lambda z: abs(z - m0))[:17]
        out = sorted(center)
    return out


def compute_metrics(xp: np.ndarray, xm: np.ndarray):
    if xp.size < 4 or xm.size < 4:
        return None
    mu_p = float(np.mean(xp))
    mu_m = float(np.mean(xm))
    sd_p = float(np.std(xp, ddof=1))
    sd_m = float(np.std(xm, ddof=1))
    if not np.isfinite(sd_p) or sd_p <= 0:
        return None
    snre_asym_xp = (abs(mu_p - mu_m) ** 2) / (4.0 * (sd_p ** 2) + EPS)
    snre_asym_sym = (abs(mu_p - mu_m) ** 2) / (2.0 * ((sd_p ** 2) + (sd_m ** 2)) + EPS)
    return {
        "asym_xp": float(snre_asym_xp),
        "asym_sym": float(snre_asym_sym),
    }


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


def get_null_snre_channels(run_dir: str):
    p = os.path.join(run_dir, "processed_summary.json")
    if not os.path.isfile(p):
        return []
    try:
        with open(p, "r", encoding="utf-8") as f:
            j = json.load(f)
    except Exception:
        return []

    null_ch = []
    for ch in ("S1", "S2"):
        ch_obj = j.get(ch)
        if isinstance(ch_obj, dict) and ("SNRe" in ch_obj) and (ch_obj.get("SNRe") is None):
            null_ch.append(ch)
    return null_ch


def load_classical_limits_for_run(root: str, run_index: int):
    run_dir = os.path.join(root, f"run_{int(run_index):05d}")
    return load_classical_limits(run_dir)


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


def optimize_run_channel(
    run_index: int,
    run_dir: str,
    run_relpath: str,
    channel_name: str,
    homo: np.ndarray,
    mod: np.ndarray,
    fs: float,
    classical_limit: float,
    m_values,
    phase_multiplier: int,
    lag_range: int,
    clip_mode: str,
    disallow_brickwall_filters: bool,
):
    filter_defs_all = [
        ("none", None),
        ("fft_lp_0p6Rb", 0.6),
        ("fft_lp_0p8Rb", 0.8),
    ]
    if disallow_brickwall_filters:
        filter_defs = [x for x in filter_defs_all if x[0] == "none"]
    else:
        filter_defs = filter_defs_all
    detrend_defs = [
        ("none", 0),
        ("movmean_2M", 2),
    ]
    clip_defs_all = [
        ("none", 0.0),
        ("winsor_q0p005", 0.005),
    ]
    if clip_mode == "none-only":
        clip_defs = [x for x in clip_defs_all if x[0] == "none"]
    elif clip_mode == "winsor-only":
        clip_defs = [x for x in clip_defs_all if x[0] != "none"]
    else:
        clip_defs = clip_defs_all
    threshold_defs = ["mean", "median"]
    invert_defs = [False, True]
    metric_defs = ["asym_xp", "asym_sym"]
    lag_defs = list(range(-int(lag_range), int(lag_range) + 1))

    best: Candidate | None = None

    for M in m_values:
        if M < 4:
            continue
        Rb = fs / float(M)

        filtered = {}
        for filter_name, ratio in filter_defs:
            if ratio is None:
                filtered[filter_name] = homo
            else:
                filtered[filter_name] = fft_lowpass(homo, fs, ratio * Rb)

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

                        n_phase = max(1, int(phase_multiplier) * int(M))
                        for phase in range(n_phase):
                            hs = sig_lag[phase::M]
                            ms = mod_lag[phase::M]
                            n = min(hs.size, ms.size)
                            if n < 100:
                                continue
                            hs = hs[:n]
                            ms = ms[:n]

                            for threshold_name in threshold_defs:
                                if threshold_name == "mean":
                                    th = float(np.mean(ms))
                                else:
                                    th = float(np.median(ms))

                                bits = ms > th

                                for invert in invert_defs:
                                    b = (~bits) if invert else bits
                                    p = float(np.mean(b))
                                    if p < 0.05 or p > 0.95:
                                        continue

                                    xp = hs[b]
                                    xm = hs[~b]
                                    metrics = compute_metrics(xp, xm)
                                    if metrics is None:
                                        continue

                                    for metric in metric_defs:
                                        score = float(metrics[metric])
                                        snre = float(metrics["asym_xp"])
                                        margin = snre - classical_limit
                                        advantage_db = compute_advantage_db(snre, classical_limit)
                                        cand = Candidate(
                                            run_index=run_index,
                                            run_dir=run_dir,
                                            run_relpath=run_relpath,
                                            channel=channel_name,
                                            snre=snre,
                                            score=score,
                                            margin_vs_classical=margin,
                                            advantage_db=advantage_db,
                                            method=(
                                                f"filter={filter_name}; detrend={detrend_name}; clip={clip_name}; "
                                                f"threshold={threshold_name}; invert={invert}; metric={metric}; "
                                                f"M={M}; phase={phase}; lag={lag}"
                                            ),
                                            filter_name=filter_name,
                                            detrend_name=detrend_name,
                                            clip_name=clip_name,
                                            threshold_name=threshold_name,
                                            invert=invert,
                                            metric=metric,
                                            M=M,
                                            phase=phase,
                                            lag=lag,
                                            n_points=int(n),
                                            class_balance=p,
                                            homo_file="",
                                            mod_file="",
                                        )
                                        if (best is None) or (cand.score > best.score):
                                            best = cand

    return best


def fmt_bool(x: bool):
    return "True" if x else "False"


def compute_advantage_db(snre: float, classical: float):
    if snre <= 0 or classical <= 0:
        return float("nan")
    return float(10.0 * math.log10(snre / classical))


def main():
    args = parse_args()
    root = args.root
    recursive_runs = bool(args.recursive_runs)
    report_path = args.report
    json_path = args.json
    sweep_tracking_json = str(args.sweep_tracking_json or "").strip()
    verbose = bool(args.verbose)
    progress_every = max(1, int(args.progress_every))
    dynamic_m = bool(args.dynamic_m)
    phase_multiplier = max(1, int(args.phase_multiplier))
    lag_range = max(0, int(args.lag_range))
    clip_mode = str(args.clip_mode)
    disallow_brickwall_filters = bool(args.disallow_brickwall_filters)
    rb_by_channel = {"S1": float(args.rb_s1), "S2": float(args.rb_s2)}
    fallback_classical_from_run = int(args.fallback_classical_from_run)
    run_index_file = str(args.run_index_file or "").strip()

    def vprint(msg: str):
        if verbose:
            print(msg, flush=True)

    m_values = [int(x.strip()) for x in args.m_values.split(",") if x.strip()]
    runs = discover_runs(root, recursive=recursive_runs)
    if not runs:
        raise SystemExit(f"No run_* folders found in {root}")
    run_index_filter = None
    if run_index_file:
        run_index_filter = load_run_index_filter(run_index_file)
        runs = [(ri, rd) for (ri, rd) in runs if ri in run_index_filter]
        if not runs:
            raise SystemExit(f"No matching run_* folders for indices from {run_index_file}")

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

    fallback_classical = None
    if fallback_classical_from_run >= 0:
        try:
            fallback_classical = load_classical_limits_for_run(root, fallback_classical_from_run)
            classical_source = (
                f"{classical_source} with fallback from run_{fallback_classical_from_run:05d}"
            )
            vprint(
                f"Loaded fallback classical values from run_{fallback_classical_from_run:05d}: "
                f"S1={fallback_classical['S1']:.6g}, S2={fallback_classical['S2']:.6g}"
            )
        except Exception as e:
            vprint(
                f"Warning: could not load fallback classical values from run_{fallback_classical_from_run:05d}: {e}"
            )

    specs = channel_spec()

    per_run = []
    best_by_channel = {}
    beat_classical = defaultdict(list)
    method_counter = Counter()
    skipped_null_snre_runs = []

    vprint(
        f"Starting optimization: root={root}, runs={len(runs)}, "
        f"m_values={m_values}, dynamic_m={dynamic_m}, phase_multiplier={phase_multiplier}, "
        f"lag_range={lag_range}, clip_mode={clip_mode}, disallow_brickwall_filters={disallow_brickwall_filters}, "
        f"rb_s1={rb_by_channel['S1']}, rb_s2={rb_by_channel['S2']}, "
        f"report={report_path}, json={json_path}, run_index_file={run_index_file or 'n/a'}, "
        f"recursive_runs={recursive_runs}"
    )

    for run_num, (run_index, run_dir) in enumerate(runs, start=1):
        t0 = dt.datetime.now(dt.timezone.utc)
        run_relpath = os.path.relpath(run_dir, root)
        vprint(f"[{run_num}/{len(runs)}] run_{run_index:05d} start")
        try:
            null_channels = get_null_snre_channels(run_dir)
            if null_channels:
                skipped_null_snre_runs.append({
                    "run_index": run_index,
                    "run_dir": run_dir,
                    "run_relpath": run_relpath,
                    "null_snre_channels": list(null_channels),
                })
                per_run.append(
                    {
                        "run_index": run_index,
                        "run_dir": run_dir,
                        "run_relpath": run_relpath,
                        "skipped": True,
                        "skip_reason": "null_SNRe_in_metadata",
                        "null_snre_channels": list(null_channels),
                    }
                )
                vprint(
                    f"[{run_num}/{len(runs)}] run_{run_index:05d} skipped: "
                    f"null SNRe in {', '.join(null_channels)}"
                )
                continue

            if classical_lookup and run_index in classical_lookup:
                classical = classical_lookup[run_index]
            else:
                try:
                    classical = load_classical_limits(run_dir)
                except FileNotFoundError:
                    if fallback_classical is not None:
                        classical = fallback_classical
                        vprint(
                            f"[{run_num}/{len(runs)}] run_{run_index:05d} missing processed_summary; "
                            f"using fallback classical from run_{fallback_classical_from_run:05d}"
                        )
                    else:
                        raise
                if classical_lookup:
                    vprint(
                        f"[{run_num}/{len(runs)}] run_{run_index:05d} "
                        "missing in sweep tracking; using processed_summary classical values"
                    )

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
            fs = 1.0 / float(t_ref[1] - t_ref[0])

            row = {
                "run_index": run_index,
                "run_dir": run_dir,
                "run_relpath": run_relpath,
            }
            ch_summaries = []
            for ch_name, ch_cfg in specs.items():
                h_idx = ch_cfg["homo"]
                m_idx = ch_cfg["mod"]
                if dynamic_m:
                    rb = rb_by_channel[ch_name]
                    if rb <= 0:
                        raise ValueError(f"Invalid bit rate for {ch_name}: {rb}")
                    m0 = max(4, int(round(fs / rb)))
                    m_candidates_set = {m0}
                    for dm in (-2, -1, 1, 2):
                        if (m0 + dm) >= 4:
                            m_candidates_set.add(m0 + dm)
                    for m_fallback in m_values:
                        if int(m_fallback) >= 4:
                            m_candidates_set.add(int(m_fallback))
                    m_candidates = sorted(m_candidates_set)
                else:
                    m_candidates = m_values
                best = optimize_run_channel(
                    run_index,
                    run_dir,
                    run_relpath,
                    ch_name,
                    wave[h_idx],
                    wave[m_idx],
                    fs,
                    classical[ch_name],
                    m_candidates,
                    phase_multiplier,
                    lag_range,
                    clip_mode,
                    disallow_brickwall_filters,
                )
                if best is None:
                    continue
                best.homo_file = os.path.basename(files[h_idx])
                best.mod_file = os.path.basename(files[m_idx])
                row[ch_name] = {
                    "snre": best.snre,
                    "classical": classical[ch_name],
                    "margin": best.margin_vs_classical,
                    "advantage_db": best.advantage_db,
                    "method": best.method,
                }
                ch_summaries.append(
                    f"{ch_name}: SNRe={best.snre:.6g}, SNR_C={classical[ch_name]:.6g}, "
                    f"margin={best.margin_vs_classical:+.6g}, adv_dB={best.advantage_db:+.6g}, "
                    f"method={best.filter_name}/{best.detrend_name}/"
                    f"{best.clip_name}/thr={best.threshold_name}/inv={best.invert}/M={best.M}/"
                    f"phase={best.phase}/lag={best.lag}/Mset={len(m_candidates)}"
                )
                method_counter[(best.filter_name, best.detrend_name, best.clip_name, best.threshold_name, best.invert, best.metric, best.M, best.lag)] += 1

                if ch_name not in best_by_channel or best.snre > best_by_channel[ch_name].snre:
                    best_by_channel[ch_name] = best

                if best.margin_vs_classical > 0:
                    beat_classical[ch_name].append({
                        "run_index": run_index,
                        "run_dir": run_dir,
                        "run_relpath": run_relpath,
                        "snre": best.snre,
                        "classical": classical[ch_name],
                        "margin": best.margin_vs_classical,
                        "advantage_db": best.advantage_db,
                    })

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
                "metric": k[5],
                "M": k[6],
                "lag": k[7],
            },
            "count": count,
        }

    result = {
        "generated_utc": ts,
        "root": root,
        "num_runs": len(runs),
        "m_values": m_values,
        "recursive_runs": recursive_runs,
        "dynamic_m": dynamic_m,
        "phase_multiplier": phase_multiplier,
        "lag_range": lag_range,
        "clip_mode": clip_mode,
        "disallow_brickwall_filters": disallow_brickwall_filters,
        "classical_source": classical_source,
        "best_by_channel": {
            ch: {
                "run_index": c.run_index,
                "run_dir": c.run_dir,
                "run_relpath": c.run_relpath,
                "snre": c.snre,
                "margin_vs_classical": c.margin_vs_classical,
                "advantage_db": c.advantage_db,
                "method": c.method,
                "filter": c.filter_name,
                "detrend": c.detrend_name,
                "clip": c.clip_name,
                "threshold": c.threshold_name,
                "invert": c.invert,
                "metric": c.metric,
                "M": c.M,
                "phase": c.phase,
                "lag": c.lag,
                "n_points": c.n_points,
                "class_balance": c.class_balance,
                "homo_file": c.homo_file,
                "mod_file": c.mod_file,
                "homo_path": os.path.join(c.run_dir, c.homo_file) if c.homo_file else "",
                "mod_path": os.path.join(c.run_dir, c.mod_file) if c.mod_file else "",
            }
            for ch, c in best_by_channel.items()
        },
        "beat_classical_indices": {
            ch: sorted(set(int(x["run_index"]) for x in v)) for ch, v in beat_classical.items()
        },
        "beat_classical_runs": {
            ch: sorted(
                v,
                key=lambda r: (
                    float(r.get("margin", float("-inf"))),
                    int(r.get("run_index", -1)),
                    str(r.get("run_relpath", "")),
                ),
                reverse=True,
            )
            for ch, v in beat_classical.items()
        },
        "top_method": top_method,
        "skipped_null_snre_runs": skipped_null_snre_runs,
        "per_run": per_run,
    }

    os.makedirs(os.path.dirname(json_path), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    vprint(f"Wrote JSON: {json_path}")

    lines = []
    lines.append("# SNR Post-Processing Optimization Report")
    lines.append("")
    lines.append(f"Generated (UTC): {ts}")
    lines.append(f"Runs processed: {len(runs)}")
    lines.append(f"Classical reference source: {classical_source}")
    lines.append("")
    lines.append("## Best Extracted SNR by Channel")
    lines.append("")
    lines.append("| Channel | Best Run Index | Max Extracted SNRe | Classical SNR_C (same run) | Margin | Advantage in dB | Run Directory | Homodyne Path | Mod Path |")
    lines.append("|---|---:|---:|---:|---:|---:|---|---|---|")
    for ch in ["S1", "S2"]:
        b = best_by_channel.get(ch)
        if not b:
            lines.append(f"| {ch} | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")
            continue
        adv_txt = f"{b.advantage_db:+.6f}" if np.isfinite(b.advantage_db) else "n/a"
        homo_path = os.path.join(b.run_dir, b.homo_file) if b.homo_file else "n/a"
        mod_path = os.path.join(b.run_dir, b.mod_file) if b.mod_file else "n/a"
        lines.append(
            f"| {ch} | {b.run_index} | {b.snre:.6f} | {b.snre - b.margin_vs_classical:.6f} | {b.margin_vs_classical:+.6f} | {adv_txt} | `{b.run_dir}` | `{homo_path}` | `{mod_path}` |"
        )

    lines.append("")
    lines.append("## Classical-Limit Flags")
    lines.append("")
    for ch in ["S1", "S2"]:
        flagged_rows = beat_classical.get(ch, [])
        flagged_unique = sorted(set(int(x["run_index"]) for x in flagged_rows))
        if flagged_rows:
            lines.append(
                f"- {ch}: {len(flagged_rows)} advantaged run-path entries "
                f"({len(flagged_unique)} unique run indices)"
            )
        else:
            lines.append(f"- {ch}: no run exceeded classical SNR_C under the tested method sweep")
    lines.append("")
    lines.append("## All Advantage Datasets")
    lines.append("")
    lines.append("| Channel | Run Index | Margin | Advantage in dB | SNRe | Classical SNR_C | Run Path |")
    lines.append("|---|---:|---:|---:|---:|---:|---|")
    any_flagged = False
    for ch in ["S1", "S2"]:
        flagged_rows = beat_classical.get(ch, [])
        for item in sorted(
            flagged_rows,
            key=lambda r: (float(r["margin"]), int(r["run_index"]), str(r["run_relpath"])),
            reverse=True,
        ):
            any_flagged = True
            adv_txt = f"{item['advantage_db']:+.6f}" if np.isfinite(item["advantage_db"]) else "n/a"
            lines.append(
                f"| {ch} | {int(item['run_index'])} | {float(item['margin']):+.6f} | "
                f"{adv_txt} | {float(item['snre']):.6f} | {float(item['classical']):.6f} | "
                f"`{str(item['run_relpath'])}` |"
            )
    if not any_flagged:
        lines.append("| n/a | n/a | n/a | n/a | n/a | n/a | n/a |")

    lines.append("")
    lines.append("## Skipped Runs")
    lines.append("")
    if skipped_null_snre_runs:
        lines.append(
            f"- skipped due to null SNRe in processed_summary metadata: {len(skipped_null_snre_runs)} run(s)"
        )
        lines.append("- indices: " + ", ".join(str(int(r["run_index"])) for r in skipped_null_snre_runs))
    else:
        lines.append("- no runs were skipped for null SNRe metadata")

    lines.append("")
    lines.append("## Best Method Settings (Per Channel Winner)")
    lines.append("")
    for ch in ["S1", "S2"]:
        b = best_by_channel.get(ch)
        if not b:
            continue
        lines.append(f"### {ch}")
        lines.append(f"- run index: {b.run_index}")
        lines.append(f"- filter: `{b.filter_name}`")
        lines.append(f"- detrend: `{b.detrend_name}`")
        lines.append(f"- clip: `{b.clip_name}`")
        lines.append(f"- threshold: `{b.threshold_name}`")
        lines.append(f"- modulation invert: `{fmt_bool(b.invert)}`")
        lines.append(f"- metric: `{b.metric}`")
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
            "The most consistently successful method across per-run winners used "
            f"`{s['filter']}` filtering with `{s['detrend']}` detrending, `{s['clip']}` clipping, "
            f"`{s['threshold']}` thresholding, inversion=`{fmt_bool(bool(s['invert']))}`, "
            f"metric=`{s['metric']}`, `M={s['M']}`, and lag=`{s['lag']}`. "
            f"It appeared in {top_method['count']} winning run-channel selections."
        )
    else:
        lines.append("No successful method candidates were produced.")

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- Optimization objective matched deterministic extraction style and evaluated multiple post-processing pipelines.")
    lines.append("- `Advantage in dB` is computed as `10*log10(SNRe/SNR_C)`.")
    lines.append("- Channel mapping used: S1 homodyne `scope_*_2.csv` with modulation `scope_*_1.csv`; S2 homodyne `scope_*_3.csv` with modulation `scope_*_4.csv`.")
    lines.append(f"- Classical SNR comparison source: `{classical_source}`.")
    lines.append(
        f"- Dynamic M inference: `{dynamic_m}` (M=round(Fs/Rb), Rb_S1={rb_by_channel['S1']:.6g} Hz, "
        f"Rb_S2={rb_by_channel['S2']:.6g} Hz); phase sweep span: `phase_multiplier*M`; "
        f"lag sweep: `[-{lag_range}, +{lag_range}]`."
    )
    lines.append(f"- Clip mode: `{clip_mode}`.")
    lines.append(f"- Brick-wall filters disallowed: `{disallow_brickwall_filters}`.")
    lines.append(f"- Run discovery mode: `{'recursive' if recursive_runs else 'single-level'}`.")

    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    vprint(f"Wrote report: {report_path}")
    vprint("Optimization complete.")


if __name__ == "__main__":
    main()
