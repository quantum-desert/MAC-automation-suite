#!/usr/bin/env python3
import argparse
import datetime as dt
import glob
import json
import math
import os
from collections import defaultdict
from dataclasses import dataclass

import numpy as np

EPS = 1e-18


@dataclass
class Candidate:
    run_index: int
    run_dir: str
    channel: str
    snre: float
    score: float
    margin_vs_classical: float
    advantage_db: float
    method: str
    n_points: int
    class_balance: float
    trim_mode: str
    trim_points: int
    phase: int
    phase_ref: int
    phase_dist: int
    M: int
    lag: int
    filter_name: str
    detrend_name: str
    clip_name: str
    threshold_name: str
    invert: bool
    metric: str
    homo_file: str
    mod_file: str


def parse_args():
    p = argparse.ArgumentParser(description="Test optimizer: peak-referenced phase with trim")
    p.add_argument("--root", required=True)
    p.add_argument("--base-results-json", required=True, help="Use fixed filter chain from this non-trim JSON")
    p.add_argument("--report", required=True)
    p.add_argument("--json", required=True)
    p.add_argument("--recursive-runs", action="store_true")
    p.add_argument("--min-downsampled", type=int, default=500)
    p.add_argument("--trim-step", type=int, default=1, help="Trim step in downsampled points")
    p.add_argument("--peak-penalty", type=float, default=0.15, help="Penalty weight for distance from phase_ref")
    p.add_argument(
        "--phase-opt-mode",
        default="penalized",
        choices=["penalized", "snre-only"],
        help="Phase optimization objective per trim candidate.",
    )
    p.add_argument(
        "--replace-brickwall-with-causal-lpf",
        action="store_true",
        help="Replace fft_lp_* filter names with a causal one-pole low-pass of matched cutoff.",
    )
    p.add_argument(
        "--causal-lpf-cutoff-scale",
        type=float,
        default=1.0,
        help="Scale factor on LPF cutoff when replacing brick-wall filters (e.g., 0.5 is more aggressive).",
    )
    p.add_argument(
        "--causal-lpf-stages",
        type=int,
        default=1,
        help="Number of cascaded one-pole LPF stages when replacing brick-wall filters.",
    )
    p.add_argument("--sweep-tracking-json", default="")
    p.add_argument("--disallow-brickwall-filters", action="store_true")
    p.add_argument("--verbose", action="store_true")
    p.add_argument("--progress-every", type=int, default=1)
    return p.parse_args()


def discover_runs(root: str, recursive: bool):
    entries = []
    pats = ["run_*", "*_run_*"]
    if recursive:
        for pat in pats:
            entries.extend(glob.glob(os.path.join(root, "**", pat), recursive=True))
    else:
        for pat in pats:
            entries.extend(glob.glob(os.path.join(root, pat)))
    entries = sorted(set(entries))
    out = []
    seen = set()
    for d in entries:
        if not os.path.isdir(d):
            continue
        rd = os.path.realpath(d)
        if rd in seen:
            continue
        seen.add(rd)
        try:
            idx = int(os.path.basename(d).split("_")[-1])
        except Exception:
            continue
        out.append((idx, d))
    return out


def read_csv_two_cols(path: str):
    data = np.loadtxt(path, delimiter=",", skiprows=4)
    return data[:, 0], data[:, 1]


def find_scope_file(run_dir: str, channel_idx: int):
    m = sorted(glob.glob(os.path.join(run_dir, f"scope_*_{channel_idx}.csv")))
    if not m:
        raise FileNotFoundError(f"Missing scope file channel={channel_idx} in {run_dir}")
    return m[0]


def fft_lowpass(x: np.ndarray, fs: float, cutoff_hz: float):
    if cutoff_hz <= 0:
        return np.zeros_like(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(x.size, d=1.0 / fs)
    return np.fft.irfft(X * (f <= cutoff_hz).astype(np.float64), n=x.size)


def causal_one_pole_lowpass(x: np.ndarray, fs: float, cutoff_hz: float):
    if cutoff_hz <= 0:
        return np.zeros_like(x)
    dt = 1.0 / float(fs)
    tau = 1.0 / (2.0 * math.pi * float(cutoff_hz))
    alpha = dt / (tau + dt)
    y = np.empty_like(x, dtype=np.float64)
    if x.size == 0:
        return y
    y[0] = float(x[0])
    for i in range(1, x.size):
        y[i] = y[i - 1] + alpha * (float(x[i]) - y[i - 1])
    return y


def moving_average(x: np.ndarray, window: int):
    if window <= 1:
        return x.copy()
    k = np.ones(window, dtype=np.float64) / float(window)
    return np.convolve(x, k, mode="same")


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


def load_classical_limits(run_dir: str):
    j = json.load(open(os.path.join(run_dir, "processed_summary.json"), "r", encoding="utf-8"))
    return {"S1": float(j["S1"]["SNR_C"]), "S2": float(j["S2"]["SNR_C"])}


def load_classical_lookup_from_sweep(path: str):
    data = json.load(open(path, "r", encoding="utf-8"))
    rows = data.get("rows", []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
    lookup = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        run = row.get("run", row.get("runIndex", row.get("run_index")))
        if run is None:
            continue
        try:
            run = int(run)
        except Exception:
            continue
        s1 = row.get("S1_SNR_C", row.get("S1", {}).get("SNR_C") if isinstance(row.get("S1"), dict) else None)
        s2 = row.get("S2_SNR_C", row.get("S2", {}).get("SNR_C") if isinstance(row.get("S2"), dict) else None)
        if s1 is None or s2 is None:
            continue
        try:
            lookup[run] = {"S1": float(s1), "S2": float(s2)}
        except Exception:
            pass
    return lookup


def load_fixed_channel_configs(base_results_json: str):
    j = json.load(open(base_results_json, "r", encoding="utf-8"))
    best = j.get("best_by_channel", {})
    cfg = {}
    for ch in ("S1", "S2"):
        c = best[ch]
        cfg[ch] = {
            "filter": str(c["filter"]),
            "detrend": str(c["detrend"]),
            "clip": str(c["clip"]),
            "threshold": str(c["threshold"]),
            "invert": bool(c["invert"]),
            "metric": str(c["metric"]),
            "M": int(c["M"]),
            "lag": int(c["lag"]),
        }
    return cfg


def is_brickwall_filter_name(filter_name: str):
    n = str(filter_name or "").lower()
    return n.startswith("fft_lp_") or n.startswith("fft_hp_")


def apply_filter_from_name(
    sig: np.ndarray,
    fs: float,
    M: int,
    filter_name: str,
    replace_brickwall_with_causal_lpf: bool,
    causal_lpf_cutoff_scale: float,
    causal_lpf_stages: int,
):
    rb = fs / float(M)
    cut_scale = max(1e-6, float(causal_lpf_cutoff_scale))
    stages = max(1, int(causal_lpf_stages))

    def maybe_causal_lp(x: np.ndarray, cutoff: float):
        if not replace_brickwall_with_causal_lpf:
            return fft_lowpass(x, fs, cutoff)
        y = x
        c = float(cutoff) * cut_scale
        for _ in range(stages):
            y = causal_one_pole_lowpass(y, fs, c)
        return y

    if filter_name == "none":
        return sig
    if filter_name == "fft_lp_0p6Rb":
        return maybe_causal_lp(sig, 0.6 * rb)
    if filter_name == "fft_lp_0p8Rb":
        return maybe_causal_lp(sig, 0.8 * rb)
    raise ValueError(f"Unsupported fixed filter: {filter_name}")


def apply_detrend_from_name(sig: np.ndarray, M: int, detrend_name: str):
    if detrend_name == "none":
        return sig
    if detrend_name == "movmean_2M":
        return sig - moving_average(sig, max(3, int(2 * M)))
    raise ValueError(f"Unsupported fixed detrend: {detrend_name}")


def apply_clip_from_name(sig: np.ndarray, clip_name: str):
    if clip_name == "none":
        return sig
    if clip_name == "winsor_q0p005":
        return winsorize(sig, 0.005)
    raise ValueError(f"Unsupported fixed clip: {clip_name}")


def compute_metrics(xp: np.ndarray, xm: np.ndarray):
    if xp.size < 4 or xm.size < 4:
        return None
    mu_p = float(np.mean(xp))
    mu_m = float(np.mean(xm))
    var_p = float(np.var(xp, ddof=1))
    var_m = float(np.var(xm, ddof=1))
    if (not np.isfinite(var_p)) or var_p <= 0 or (not np.isfinite(var_m)) or var_m < 0:
        return None
    dmu2 = abs(mu_p - mu_m) ** 2
    return {
        "asym_xp": float(dmu2 / (4.0 * var_p + EPS)),
        "asym_sym": float(dmu2 / (2.0 * (var_p + var_m) + EPS)),
    }


def circ_dist(a: int, b: int, m: int):
    d = abs(a - b) % m
    return min(d, m - d)


def optimize_run_channel_peakpen(
    run_index: int,
    run_dir: str,
    channel: str,
    homo: np.ndarray,
    mod: np.ndarray,
    fs: float,
    classical: float,
    cfg: dict,
    min_downsampled: int,
    trim_step: int,
    peak_penalty: float,
    replace_brickwall_with_causal_lpf: bool,
    causal_lpf_cutoff_scale: float,
    causal_lpf_stages: int,
    phase_opt_mode: str,
):
    M = int(cfg["M"])
    lag = int(cfg["lag"])
    if M < 4:
        return None
    sig = apply_filter_from_name(
        homo,
        fs,
        M,
        cfg["filter"],
        replace_brickwall_with_causal_lpf,
        causal_lpf_cutoff_scale,
        causal_lpf_stages,
    )
    sig = apply_detrend_from_name(sig, M, cfg["detrend"])
    sig = apply_clip_from_name(sig, cfg["clip"])
    sig_lag, mod_lag = apply_lag(sig, mod, lag)
    n_raw = min(sig_lag.size, mod_lag.size)
    if n_raw < (min_downsampled + 1) * M:
        return None
    sig_lag = sig_lag[:n_raw]
    mod_lag = mod_lag[:n_raw]

    max_trim = int(n_raw // M) - min_downsampled
    if max_trim < 0:
        return None

    best = None
    best_none = None
    best_trimmed = None
    trim_step = max(1, int(trim_step))

    def eval_trim(trim_mode: str, trim_points: int):
        nonlocal best, best_none, best_trimmed
        rt = int(trim_points) * int(M)
        if trim_mode == "none":
            l, r = 0, n_raw
        elif trim_mode == "trim_start":
            l, r = rt, n_raw
        else:
            l, r = 0, n_raw - rt
        if r <= l:
            return
        seg_sig = sig_lag[l:r]
        seg_mod = mod_lag[l:r]

        # Phase reference from on-peak assumption: maximize |sample amplitude|.
        phase_ref = None
        phase_ref_amp = None
        for ph in range(M):
            hs = seg_sig[ph::M]
            if hs.size < min_downsampled:
                continue
            amp = float(np.mean(np.abs(hs)))
            if (phase_ref is None) or (amp > phase_ref_amp):
                phase_ref = ph
                phase_ref_amp = amp
        if phase_ref is None:
            return

        for ph in range(M):
            hs = seg_sig[ph::M]
            ms = seg_mod[ph::M]
            n = min(hs.size, ms.size)
            if n < min_downsampled:
                continue
            hs = hs[:n]
            ms = ms[:n]
            th = float(np.mean(ms)) if cfg["threshold"] == "mean" else float(np.median(ms))
            bits = ms > th
            b = (~bits) if cfg["invert"] else bits
            p = float(np.mean(b))
            if p < 0.05 or p > 0.95:
                continue
            m = compute_metrics(hs[b], hs[~b])
            if m is None:
                continue
            snre = float(m["asym_xp"])
            base_score = float(m[cfg["metric"]])
            d = circ_dist(ph, phase_ref, M)
            penalty = float(peak_penalty) * ((float(d) / float(M)) ** 2)
            if str(phase_opt_mode) == "snre-only":
                score = float(m["asym_xp"])
            else:
                score = base_score - penalty
            margin = snre - classical
            adv_db = float(10.0 * math.log10(snre / classical)) if (snre > 0 and classical > 0) else float("nan")

            cand = Candidate(
                run_index=run_index,
                run_dir=run_dir,
                channel=channel,
                snre=snre,
                score=score,
                margin_vs_classical=margin,
                advantage_db=adv_db,
                method=(
                    f"fixed(filter={cfg['filter']}; detrend={cfg['detrend']}; clip={cfg['clip']}; "
                    f"threshold={cfg['threshold']}; invert={cfg['invert']}; metric={cfg['metric']}; "
                    f"M={M}; lag={lag}); trim={trim_mode}:{trim_points}; "
                    f"phase_ref={phase_ref}; phase={ph}; peak_penalty={peak_penalty}"
                ),
                n_points=int(n),
                class_balance=float(p),
                trim_mode=trim_mode,
                trim_points=int(trim_points),
                phase=int(ph),
                phase_ref=int(phase_ref),
                phase_dist=int(d),
                M=M,
                lag=lag,
                filter_name=cfg["filter"],
                detrend_name=cfg["detrend"],
                clip_name=cfg["clip"],
                threshold_name=cfg["threshold"],
                invert=bool(cfg["invert"]),
                metric=cfg["metric"],
                homo_file="",
                mod_file="",
            )
            if (best is None) or (cand.score > best.score):
                best = cand
            if trim_mode == "none":
                if (best_none is None) or (cand.score > best_none.score):
                    best_none = cand
            else:
                if (best_trimmed is None) or (cand.score > best_trimmed.score):
                    best_trimmed = cand

    eval_trim("none", 0)
    for k in range(trim_step, max_trim + 1, trim_step):
        eval_trim("trim_start", k)
        eval_trim("trim_end", k)

    return best, best_none, best_trimmed


def channel_spec():
    return {"S1": {"homo": 2, "mod": 1}, "S2": {"homo": 3, "mod": 4}}


def main():
    a = parse_args()
    runs = discover_runs(a.root, bool(a.recursive_runs))
    if not runs:
        raise SystemExit(f"No run_* folders found in {a.root}")
    cfg = load_fixed_channel_configs(a.base_results_json)
    if a.disallow_brickwall_filters:
        bad = [ch for ch in ("S1", "S2") if is_brickwall_filter_name(cfg[ch]["filter"])]
        if bad:
            raise SystemExit(
                "Base results JSON uses brick-wall filter(s) for "
                + ", ".join(bad)
                + ". Provide a non-brickwall base JSON."
            )

    classical_lookup = {}
    classical_source = "processed_summary.json"
    if str(a.sweep_tracking_json).strip():
        classical_lookup = load_classical_lookup_from_sweep(a.sweep_tracking_json)
        if classical_lookup:
            classical_source = f"sweep_tracking.json ({a.sweep_tracking_json})"

    per_run = []
    best_by_channel = {}
    best_by_channel_untrim = {}
    best_by_channel_trimmed = {}
    beat = defaultdict(list)
    spec = channel_spec()

    if a.verbose:
        print(
            f"Start peak-penalty test optimizer: root={a.root}, runs={len(runs)}, "
            f"recursive={bool(a.recursive_runs)}, min_downsampled={a.min_downsampled}, "
            f"trim_step={a.trim_step}, peak_penalty={a.peak_penalty}, "
            f"phase_opt_mode={a.phase_opt_mode}, causal_lpf_scale={a.causal_lpf_cutoff_scale}, "
            f"causal_lpf_stages={a.causal_lpf_stages}",
            flush=True,
        )

    for i, (run_index, run_dir) in enumerate(runs, start=1):
        t0 = dt.datetime.now(dt.timezone.utc)
        try:
            classical = classical_lookup.get(run_index, load_classical_limits(run_dir))
            files = {}
            wave = {}
            t_ref = None
            for ci in [1, 2, 3, 4]:
                f = find_scope_file(run_dir, ci)
                t, y = read_csv_two_cols(f)
                files[ci] = f
                wave[ci] = y
                if t_ref is None:
                    t_ref = t
            fs = 1.0 / float(np.mean(np.diff(t_ref)))

            row = {"run_index": run_index, "run_dir": run_dir}
            msgs = []
            for ch, ch_cfg in spec.items():
                cand, cand_none, cand_trim = optimize_run_channel_peakpen(
                    run_index=run_index,
                    run_dir=run_dir,
                    channel=ch,
                    homo=wave[ch_cfg["homo"]],
                    mod=wave[ch_cfg["mod"]],
                    fs=fs,
                    classical=classical[ch],
                    cfg=cfg[ch],
                    min_downsampled=int(a.min_downsampled),
                    trim_step=int(a.trim_step),
                    peak_penalty=float(a.peak_penalty),
                    replace_brickwall_with_causal_lpf=bool(a.replace_brickwall_with_causal_lpf),
                    causal_lpf_cutoff_scale=float(a.causal_lpf_cutoff_scale),
                    causal_lpf_stages=int(a.causal_lpf_stages),
                    phase_opt_mode=str(a.phase_opt_mode),
                )
                if cand is None:
                    continue
                cand.homo_file = os.path.basename(files[ch_cfg["homo"]])
                cand.mod_file = os.path.basename(files[ch_cfg["mod"]])
                row[ch] = {
                    "snre": cand.snre,
                    "classical": classical[ch],
                    "margin": cand.margin_vs_classical,
                    "advantage_db": cand.advantage_db,
                    "trim_mode": cand.trim_mode,
                    "trim_points": cand.trim_points,
                    "phase": cand.phase,
                    "phase_ref": cand.phase_ref,
                    "phase_dist": cand.phase_dist,
                    "method": cand.method,
                }
                msgs.append(
                    f"{ch}: SNRe={cand.snre:.6g}, margin={cand.margin_vs_classical:+.6g}, "
                    f"trim={cand.trim_mode}:{cand.trim_points}, phase={cand.phase}, pref={cand.phase_ref}, d={cand.phase_dist}"
                )
                if (ch not in best_by_channel) or (cand.snre > best_by_channel[ch].snre):
                    best_by_channel[ch] = cand
                if cand_none is not None:
                    cand_none.homo_file = os.path.basename(files[ch_cfg["homo"]])
                    cand_none.mod_file = os.path.basename(files[ch_cfg["mod"]])
                    if (ch not in best_by_channel_untrim) or (cand_none.snre > best_by_channel_untrim[ch].snre):
                        best_by_channel_untrim[ch] = cand_none
                if cand_trim is not None:
                    cand_trim.homo_file = os.path.basename(files[ch_cfg["homo"]])
                    cand_trim.mod_file = os.path.basename(files[ch_cfg["mod"]])
                    if (ch not in best_by_channel_trimmed) or (cand_trim.snre > best_by_channel_trimmed[ch].snre):
                        best_by_channel_trimmed[ch] = cand_trim
                if cand.margin_vs_classical > 0:
                    beat[ch].append(run_index)
            per_run.append(row)
            if a.verbose and (i % max(1, int(a.progress_every)) == 0 or i == len(runs)):
                dt_s = (dt.datetime.now(dt.timezone.utc) - t0).total_seconds()
                print(f"[{i}/{len(runs)}] run_{run_index:05d} done in {dt_s:.2f}s | " + (" | ".join(msgs) if msgs else "no candidates"), flush=True)
        except Exception as e:
            per_run.append({"run_index": run_index, "run_dir": run_dir, "error": str(e)})
            if a.verbose:
                print(f"[{i}/{len(runs)}] run_{run_index:05d} ERROR: {e}", flush=True)

    ts = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = {
        "generated_utc": ts,
        "root": a.root,
        "num_runs": len(runs),
        "recursive_runs": bool(a.recursive_runs),
        "classical_source": classical_source,
        "base_results_json": a.base_results_json,
        "min_downsampled": int(a.min_downsampled),
        "trim_step": int(a.trim_step),
        "peak_penalty": float(a.peak_penalty),
        "phase_opt_mode": str(a.phase_opt_mode),
        "replace_brickwall_with_causal_lpf": bool(a.replace_brickwall_with_causal_lpf),
        "causal_lpf_cutoff_scale": float(a.causal_lpf_cutoff_scale),
        "causal_lpf_stages": int(a.causal_lpf_stages),
        "disallow_brickwall_filters": bool(a.disallow_brickwall_filters),
        "fixed_channel_configs": cfg,
        "best_by_channel": {
            ch: {
                "run_index": c.run_index,
                "run_dir": c.run_dir,
                "snre": c.snre,
                "margin_vs_classical": c.margin_vs_classical,
                "advantage_db": c.advantage_db,
                "trim_mode": c.trim_mode,
                "trim_points": c.trim_points,
                "phase": c.phase,
                "phase_ref": c.phase_ref,
                "phase_dist": c.phase_dist,
                "M": c.M,
                "lag": c.lag,
                "filter": c.filter_name,
                "detrend": c.detrend_name,
                "clip": c.clip_name,
                "threshold": c.threshold_name,
                "invert": c.invert,
                "metric": c.metric,
                "n_points": c.n_points,
                "class_balance": c.class_balance,
                "homo_file": c.homo_file,
                "mod_file": c.mod_file,
                "homo_path": os.path.join(c.run_dir, c.homo_file),
                "mod_path": os.path.join(c.run_dir, c.mod_file),
                "method": c.method,
            }
            for ch, c in best_by_channel.items()
        },
        "beat_classical_indices": {ch: sorted(v) for ch, v in beat.items()},
        "best_by_channel_untrimmed_only": {
            ch: {
                "run_index": c.run_index,
                "run_dir": c.run_dir,
                "snre": c.snre,
                "margin_vs_classical": c.margin_vs_classical,
                "advantage_db": c.advantage_db,
                "trim_mode": c.trim_mode,
                "trim_points": c.trim_points,
                "phase": c.phase,
                "phase_ref": c.phase_ref,
                "phase_dist": c.phase_dist,
                "method": c.method,
            }
            for ch, c in best_by_channel_untrim.items()
        },
        "best_by_channel_trimmed_only": {
            ch: {
                "run_index": c.run_index,
                "run_dir": c.run_dir,
                "snre": c.snre,
                "margin_vs_classical": c.margin_vs_classical,
                "advantage_db": c.advantage_db,
                "trim_mode": c.trim_mode,
                "trim_points": c.trim_points,
                "phase": c.phase,
                "phase_ref": c.phase_ref,
                "phase_dist": c.phase_dist,
                "method": c.method,
            }
            for ch, c in best_by_channel_trimmed.items()
        },
        "per_run": per_run,
    }

    os.makedirs(os.path.dirname(a.json), exist_ok=True)
    json.dump(out, open(a.json, "w", encoding="utf-8"), indent=2)

    lines = []
    lines.append("# Peak-Penalty Phase + Trim Test Report")
    lines.append("")
    lines.append(f"Generated (UTC): {ts}")
    lines.append(f"Runs processed: {len(runs)}")
    lines.append(f"Classical reference source: {classical_source}")
    lines.append(f"Base fixed-config source: {a.base_results_json}")
    lines.append(f"Min downsampled points: {int(a.min_downsampled)}")
    lines.append(f"Trim step: {int(a.trim_step)}")
    lines.append(f"Peak penalty weight: {float(a.peak_penalty):.6g}")
    lines.append(f"Phase optimization mode: {str(a.phase_opt_mode)}")
    lines.append(f"Replace brick-wall with causal LPF: {bool(a.replace_brickwall_with_causal_lpf)}")
    lines.append(f"Causal LPF cutoff scale: {float(a.causal_lpf_cutoff_scale):.6g}")
    lines.append(f"Causal LPF stages: {int(a.causal_lpf_stages)}")
    lines.append("")
    lines.append("## Best Extracted SNR by Channel")
    lines.append("")
    lines.append("| Channel | Best Run Index | Max Extracted SNRe | Classical SNR_C | Margin | Advantage dB | Trim | Phase (chosen/ref/dist) | Run Directory |")
    lines.append("|---|---:|---:|---:|---:|---:|---|---|---|")
    for ch in ("S1", "S2"):
        b = best_by_channel.get(ch)
        if not b:
            lines.append(f"| {ch} | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")
            continue
        lines.append(
            f"| {ch} | {b.run_index} | {b.snre:.6f} | {b.snre - b.margin_vs_classical:.6f} | "
            f"{b.margin_vs_classical:+.6f} | {b.advantage_db:+.6f} | {b.trim_mode}:{b.trim_points} | "
            f"{b.phase}/{b.phase_ref}/{b.phase_dist} | `{b.run_dir}` |"
        )
    lines.append("")
    lines.append("## Trimmed vs Untrimmed Comparison")
    lines.append("")
    lines.append("| Channel | Mode | Run Index | SNRe | Margin | Advantage dB | Trim | Phase/ref/dist | Run Directory |")
    lines.append("|---|---|---:|---:|---:|---:|---|---|---|")
    for ch in ("S1", "S2"):
        u = best_by_channel_untrim.get(ch)
        t = best_by_channel_trimmed.get(ch)
        if u is None:
            lines.append(f"| {ch} | untrimmed (`none`) | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")
        else:
            lines.append(
                f"| {ch} | untrimmed (`none`) | {u.run_index} | {u.snre:.6f} | {u.margin_vs_classical:+.6f} | "
                f"{u.advantage_db:+.6f} | {u.trim_mode}:{u.trim_points} | {u.phase}/{u.phase_ref}/{u.phase_dist} | `{u.run_dir}` |"
            )
        if t is None:
            lines.append(f"| {ch} | trimmed | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")
        else:
            lines.append(
                f"| {ch} | trimmed | {t.run_index} | {t.snre:.6f} | {t.margin_vs_classical:+.6f} | "
                f"{t.advantage_db:+.6f} | {t.trim_mode}:{t.trim_points} | {t.phase}/{t.phase_ref}/{t.phase_dist} | `{t.run_dir}` |"
            )
    lines.append("")
    lines.append("## Classical-Limit Flags")
    lines.append("")
    for ch in ("S1", "S2"):
        idx = sorted(beat.get(ch, []))
        if idx:
            lines.append(f"- {ch}: beats classical at run indices {', '.join(str(x) for x in idx)}")
        else:
            lines.append(f"- {ch}: no positive margin")
    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- Phase reference is estimated per trim candidate by maximizing mean absolute sampled amplitude over phase.")
    lines.append("- Selection objective is `score = metric - peak_penalty * (circ_phase_distance/M)^2`.")
    lines.append("- `phase_opt_mode=snre-only` instead chooses phase by maximum SNRe directly.")
    lines.append("- When enabled, brick-wall LP filters are replaced by a causal one-pole low-pass of matched cutoff.")
    lines.append("- SNRe reported is asym_xp; metric is inherited from base fixed channel config.")

    os.makedirs(os.path.dirname(a.report), exist_ok=True)
    open(a.report, "w", encoding="utf-8").write("\n".join(lines) + "\n")

    if a.verbose:
        print(f"Wrote JSON: {a.json}", flush=True)
        print(f"Wrote report: {a.report}", flush=True)
        print("Peak-penalty trim optimization complete.", flush=True)


if __name__ == "__main__":
    main()
