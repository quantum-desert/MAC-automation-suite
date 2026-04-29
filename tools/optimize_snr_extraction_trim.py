#!/usr/bin/env python3
import argparse
import datetime as dt
import glob
import json
import os
from collections import defaultdict
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
    n_points: int
    class_balance: float
    trim_mode: str
    trim_points: int
    homo_file: str
    mod_file: str
    filter_name: str
    detrend_name: str
    clip_name: str
    threshold_name: str
    invert: bool
    metric: str
    M: int
    phase: int
    lag: int


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Trim-augmented deterministic SNR optimizer using fixed channel configs "
            "from a previous sweep"
        )
    )
    p.add_argument("--root", required=True, help="Directory containing run_xxxxx folders")
    p.add_argument(
        "--recursive-runs",
        action="store_true",
        help="Recursively search under --root for run_xxxxx folders",
    )
    p.add_argument("--base-results-json", required=True, help="Previous sweep results JSON used to load fixed per-channel settings")
    p.add_argument("--report", required=True, help="Path to write markdown optimization report")
    p.add_argument("--json", required=True, help="Path to write machine-readable optimization results")
    p.add_argument(
        "--sweep-tracking-json",
        default="",
        help="Optional sweep_tracking.json used for classical SNR lookup by run/runIndex",
    )
    p.add_argument("--min-downsampled", type=int, default=500, help="Minimum retained downsampled points after trimming")
    p.add_argument(
        "--disallow-brickwall-filters",
        action="store_true",
        help="Disallow fixed base configs that use FFT brick-wall filters.",
    )
    p.add_argument(
        "--redownsample-after-trim",
        action="store_true",
        help=(
            "Trim in raw-sample domain first (using trim_points*M), then re-downsample "
            "before computing SNRe."
        ),
    )
    p.add_argument("--verbose", action="store_true", help="Print per-run progress")
    p.add_argument("--progress-every", type=int, default=1, help="When verbose, print completion summaries every N runs")
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
        if os.path.isdir(entry):
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


def load_fixed_channel_configs(base_results_json: str):
    with open(base_results_json, "r", encoding="utf-8") as f:
        j = json.load(f)

    best = j.get("best_by_channel", {})
    cfgs = {}
    for ch in ("S1", "S2"):
        c = best.get(ch)
        if not isinstance(c, dict):
            raise ValueError(
                f"Missing best_by_channel.{ch} in base results JSON: {base_results_json}"
            )
        for req in (
            "filter",
            "detrend",
            "clip",
            "threshold",
            "invert",
            "metric",
            "M",
            "phase",
            "lag",
        ):
            if req not in c:
                raise ValueError(
                    f"Missing required field best_by_channel.{ch}.{req} in {base_results_json}"
                )
        cfgs[ch] = {
            "filter": str(c["filter"]),
            "detrend": str(c["detrend"]),
            "clip": str(c["clip"]),
            "threshold": str(c["threshold"]),
            "invert": bool(c["invert"]),
            "metric": str(c["metric"]),
            "M": int(c["M"]),
            "phase": int(c["phase"]),
            "lag": int(c["lag"]),
        }
    return cfgs


def is_brickwall_filter_name(filter_name: str):
    name = str(filter_name or "").lower()
    return name.startswith("fft_lp_") or name.startswith("fft_hp_")


def apply_filter_from_name(sig: np.ndarray, fs: float, M: int, filter_name: str):
    rb = fs / float(M)
    if filter_name == "none":
        return sig
    if filter_name == "fft_lp_0p6Rb":
        return fft_lowpass(sig, fs, 0.6 * rb)
    if filter_name == "fft_lp_0p8Rb":
        return fft_lowpass(sig, fs, 0.8 * rb)
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


def build_class_stats(hs: np.ndarray, b: np.ndarray):
    x = hs.astype(np.float64, copy=False)
    bp = b.astype(np.float64, copy=False)
    bm = 1.0 - bp

    cp = np.concatenate([[0.0], np.cumsum(bp)])
    cm = np.concatenate([[0.0], np.cumsum(bm)])

    sx = x
    sx2 = x * x

    sp = np.concatenate([[0.0], np.cumsum(sx * bp)])
    sm = np.concatenate([[0.0], np.cumsum(sx * bm)])

    sp2 = np.concatenate([[0.0], np.cumsum(sx2 * bp)])
    sm2 = np.concatenate([[0.0], np.cumsum(sx2 * bm)])

    return cp, cm, sp, sm, sp2, sm2


def metrics_from_segment(cp, cm, sp, sm, sp2, sm2, l: int, r: int):
    np_count = cp[r] - cp[l]
    nm_count = cm[r] - cm[l]
    n = r - l

    if np_count < 4 or nm_count < 4 or n <= 0:
        return None

    p = np_count / float(n)
    if p < 0.05 or p > 0.95:
        return None

    sum_p = sp[r] - sp[l]
    sum_m = sm[r] - sm[l]
    sumsq_p = sp2[r] - sp2[l]
    sumsq_m = sm2[r] - sm2[l]

    mu_p = sum_p / np_count
    mu_m = sum_m / nm_count

    var_p = (sumsq_p - np_count * mu_p * mu_p) / max(np_count - 1.0, 1.0)
    var_m = (sumsq_m - nm_count * mu_m * mu_m) / max(nm_count - 1.0, 1.0)

    if not np.isfinite(var_p) or var_p <= 0:
        return None
    if not np.isfinite(var_m) or var_m < 0:
        return None

    dmu2 = (abs(mu_p - mu_m) ** 2)
    snre_asym_xp = dmu2 / (4.0 * var_p + EPS)
    snre_asym_sym = dmu2 / (2.0 * (var_p + var_m) + EPS)

    return {
        "asym_xp": float(snre_asym_xp),
        "asym_sym": float(snre_asym_sym),
        "class_balance": float(p),
    }


def compute_metrics_from_vectors(xp: np.ndarray, xm: np.ndarray):
    if xp.size < 4 or xm.size < 4:
        return None
    mu_p = float(np.mean(xp))
    mu_m = float(np.mean(xm))
    var_p = float(np.var(xp, ddof=1))
    var_m = float(np.var(xm, ddof=1))
    if not np.isfinite(var_p) or var_p <= 0:
        return None
    if not np.isfinite(var_m) or var_m < 0:
        return None
    dmu2 = (abs(mu_p - mu_m) ** 2)
    snre_asym_xp = dmu2 / (4.0 * var_p + EPS)
    snre_asym_sym = dmu2 / (2.0 * (var_p + var_m) + EPS)
    return {
        "asym_xp": float(snre_asym_xp),
        "asym_sym": float(snre_asym_sym),
    }


def optimize_trim_for_run_channel(
    run_index: int,
    run_dir: str,
    run_relpath: str,
    channel_name: str,
    homo: np.ndarray,
    mod: np.ndarray,
    fs: float,
    classical_limit: float,
    cfg: dict,
    min_downsampled: int,
    redownsample_after_trim: bool,
):
    M = int(cfg["M"])
    phase = int(cfg["phase"])
    lag = int(cfg["lag"])

    if M < 4:
        return None

    sig = apply_filter_from_name(homo, fs, M, cfg["filter"])
    sig = apply_detrend_from_name(sig, M, cfg["detrend"])
    sig = apply_clip_from_name(sig, cfg["clip"])

    sig_lag, mod_lag = apply_lag(sig, mod, lag)
    n_raw = min(sig_lag.size, mod_lag.size)
    if n_raw < (min_downsampled + 1) * M:
        return None

    sig_lag = sig_lag[:n_raw]
    mod_lag = mod_lag[:n_raw]

    hs = sig_lag[phase::M]
    ms = mod_lag[phase::M]
    n = min(hs.size, ms.size)
    if n < min_downsampled:
        return None

    hs = hs[:n].astype(np.float64, copy=False)
    ms = ms[:n].astype(np.float64, copy=False)

    if cfg["threshold"] == "mean":
        th = float(np.mean(ms))
    elif cfg["threshold"] == "median":
        th = float(np.median(ms))
    else:
        raise ValueError(f"Unsupported fixed threshold: {cfg['threshold']}")

    bits = ms > th
    b = (~bits) if cfg["invert"] else bits

    cp, cm, sp, sm, sp2, sm2 = build_class_stats(hs, b)

    max_trim = n - min_downsampled
    best: Candidate | None = None

    def consider(trim_mode: str, trim_points: int, l: int, r: int):
        nonlocal best
        m = metrics_from_segment(cp, cm, sp, sm, sp2, sm2, l, r)
        if m is None:
            return

        if cfg["metric"] not in ("asym_xp", "asym_sym"):
            raise ValueError(f"Unsupported fixed metric: {cfg['metric']}")

        score = float(m[cfg["metric"]])
        snre = float(m["asym_xp"])
        margin = snre - classical_limit
        advantage_db = compute_advantage_db(snre, classical_limit)

        method = (
            f"fixed(filter={cfg['filter']}; detrend={cfg['detrend']}; clip={cfg['clip']}; "
            f"threshold={cfg['threshold']}; invert={cfg['invert']}; metric={cfg['metric']}; "
            f"M={M}; phase={phase}; lag={lag}); "
            f"trim={trim_mode}:{trim_points}"
        )

        cand = Candidate(
            run_index=run_index,
            run_dir=run_dir,
            run_relpath=run_relpath,
            channel=channel_name,
            snre=snre,
            score=score,
            margin_vs_classical=margin,
            advantage_db=advantage_db,
            method=method,
            n_points=int(r - l),
            class_balance=float(m["class_balance"]),
            trim_mode=trim_mode,
            trim_points=int(trim_points),
            homo_file="",
            mod_file="",
            filter_name=cfg["filter"],
            detrend_name=cfg["detrend"],
            clip_name=cfg["clip"],
            threshold_name=cfg["threshold"],
            invert=bool(cfg["invert"]),
            metric=cfg["metric"],
            M=M,
            phase=phase,
            lag=lag,
        )

        if (best is None) or (cand.score > best.score):
            best = cand

    if not redownsample_after_trim:
        consider("none", 0, 0, n)

        for k in range(1, max_trim + 1):
            consider("trim_start", k, k, n)
            consider("trim_end", k, 0, n - k)
    else:
        # Trim in raw domain first, then re-solve phase/downsample locations.
        def best_phase_after_trim(seg_sig: np.ndarray, seg_mod: np.ndarray):
            best_local = None
            for phase2 in range(M):
                hs2 = seg_sig[phase2::M]
                ms2 = seg_mod[phase2::M]
                n2 = min(hs2.size, ms2.size)
                if n2 < min_downsampled:
                    continue
                hs2 = hs2[:n2]
                ms2 = ms2[:n2]

                if cfg["threshold"] == "mean":
                    th2 = float(np.mean(ms2))
                else:
                    th2 = float(np.median(ms2))

                bits2 = ms2 > th2
                b2 = (~bits2) if cfg["invert"] else bits2
                p2 = float(np.mean(b2))
                if p2 < 0.05 or p2 > 0.95:
                    continue

                xp = hs2[b2]
                xm = hs2[~b2]
                m2 = compute_metrics_from_vectors(xp, xm)
                if m2 is None:
                    continue

                score2 = float(m2[cfg["metric"]])
                if (best_local is None) or (score2 > best_local["score"]):
                    best_local = {
                        "phase": int(phase2),
                        "n_points": int(n2),
                        "class_balance": float(p2),
                        "score": score2,
                        "snre": float(m2["asym_xp"]),
                    }
            return best_local

        def consider_redownsample(trim_mode: str, trim_points: int):
            nonlocal best
            raw_trim = int(trim_points) * int(M)
            if trim_mode == "none":
                l_raw, r_raw = 0, n_raw
            elif trim_mode == "trim_start":
                l_raw, r_raw = raw_trim, n_raw
            elif trim_mode == "trim_end":
                l_raw, r_raw = 0, n_raw - raw_trim
            else:
                return

            if r_raw <= l_raw:
                return

            seg_sig = sig_lag[l_raw:r_raw]
            seg_mod = mod_lag[l_raw:r_raw]
            best_phase = best_phase_after_trim(seg_sig, seg_mod)
            if best_phase is None:
                return

            score = float(best_phase["score"])
            snre = float(best_phase["snre"])
            margin = snre - classical_limit
            advantage_db = compute_advantage_db(snre, classical_limit)
            phase2 = int(best_phase["phase"])
            n2 = int(best_phase["n_points"])
            p2 = float(best_phase["class_balance"])

            method = (
                f"fixed(filter={cfg['filter']}; detrend={cfg['detrend']}; clip={cfg['clip']}; "
                f"threshold={cfg['threshold']}; invert={cfg['invert']}; metric={cfg['metric']}; "
                f"M={M}; phase={phase2}; lag={lag}); "
                f"trim={trim_mode}:{trim_points}; redownsample_after_trim=True"
            )

            cand = Candidate(
                run_index=run_index,
                run_dir=run_dir,
                run_relpath=run_relpath,
                channel=channel_name,
                snre=snre,
                score=score,
                margin_vs_classical=margin,
                advantage_db=advantage_db,
                method=method,
                n_points=int(n2),
                class_balance=float(p2),
                trim_mode=trim_mode,
                trim_points=int(trim_points),
                homo_file="",
                mod_file="",
                filter_name=cfg["filter"],
                detrend_name=cfg["detrend"],
                clip_name=cfg["clip"],
                threshold_name=cfg["threshold"],
                invert=bool(cfg["invert"]),
                metric=cfg["metric"],
                M=M,
                phase=phase2,
                lag=lag,
            )

            if (best is None) or (cand.score > best.score):
                best = cand

        consider_redownsample("none", 0)
        for k in range(1, max_trim + 1):
            consider_redownsample("trim_start", k)
            consider_redownsample("trim_end", k)

    return best


def fmt_bool(x: bool):
    return "True" if x else "False"


def compute_advantage_db(snre: float, classical: float):
    if snre <= 0 or classical <= 0:
        return float("nan")
    return float(10.0 * np.log10(snre / classical))


def main():
    args = parse_args()

    root = args.root
    recursive_runs = bool(args.recursive_runs)
    report_path = args.report
    json_path = args.json
    base_results_json = args.base_results_json
    min_downsampled = max(1, int(args.min_downsampled))
    disallow_brickwall_filters = bool(args.disallow_brickwall_filters)
    redownsample_after_trim = bool(args.redownsample_after_trim)
    sweep_tracking_json = str(args.sweep_tracking_json or "").strip()
    verbose = bool(args.verbose)
    progress_every = max(1, int(args.progress_every))

    def vprint(msg: str):
        if verbose:
            print(msg, flush=True)

    runs = discover_runs(root, recursive=recursive_runs)
    if not runs:
        raise SystemExit(f"No run_* folders found in {root}")

    cfgs = load_fixed_channel_configs(base_results_json)
    if disallow_brickwall_filters:
        bad = [ch for ch in ("S1", "S2") if is_brickwall_filter_name(cfgs[ch]["filter"])]
        if bad:
            raise SystemExit(
                "Base results JSON uses brick-wall filter(s) for "
                + ", ".join(bad)
                + ". Regenerate base JSON with brick-wall filters disabled."
            )

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
    beat_classical = defaultdict(list)
    best_by_channel = {}

    vprint(
        f"Starting trim optimization: root={root}, runs={len(runs)}, "
        f"min_downsampled={min_downsampled}, base_results={base_results_json}, "
        f"recursive_runs={recursive_runs}, redownsample_after_trim={redownsample_after_trim}, "
        f"disallow_brickwall_filters={disallow_brickwall_filters}"
    )
    vprint(
        "Fixed channel configs: "
        + "; ".join(
            f"{ch}={cfgs[ch]['filter']}/{cfgs[ch]['detrend']}/{cfgs[ch]['clip']}/"
            f"thr={cfgs[ch]['threshold']}/inv={cfgs[ch]['invert']}/metric={cfgs[ch]['metric']}/"
            f"M={cfgs[ch]['M']}/phase={cfgs[ch]['phase']}/lag={cfgs[ch]['lag']}"
            for ch in ("S1", "S2")
        )
    )

    for run_num, (run_index, run_dir) in enumerate(runs, start=1):
        t0 = dt.datetime.now(dt.timezone.utc)
        run_relpath = os.path.relpath(run_dir, root)
        vprint(f"[{run_num}/{len(runs)}] run_{run_index:05d} start")
        try:
            if classical_lookup and run_index in classical_lookup:
                classical = classical_lookup[run_index]
            else:
                classical = load_classical_limits(run_dir)
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
            fs = 1.0 / float(np.mean(np.diff(t_ref)))

            row = {"run_index": run_index, "run_dir": run_dir, "run_relpath": run_relpath}
            ch_summaries = []

            for ch_name, ch_cfg in specs.items():
                h_idx = ch_cfg["homo"]
                m_idx = ch_cfg["mod"]
                best = optimize_trim_for_run_channel(
                    run_index=run_index,
                    run_dir=run_dir,
                    run_relpath=run_relpath,
                    channel_name=ch_name,
                    homo=wave[h_idx],
                    mod=wave[m_idx],
                    fs=fs,
                    classical_limit=classical[ch_name],
                    cfg=cfgs[ch_name],
                    min_downsampled=min_downsampled,
                    redownsample_after_trim=redownsample_after_trim,
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
                    "trim_mode": best.trim_mode,
                    "trim_points": best.trim_points,
                    "method": best.method,
                }

                ch_summaries.append(
                    f"{ch_name}: SNRe={best.snre:.6g}, margin={best.margin_vs_classical:+.6g}, "
                    f"adv_dB={best.advantage_db:+.6g}, "
                    f"trim={best.trim_mode}:{best.trim_points}, n={best.n_points}"
                )

                if ch_name not in best_by_channel or best.snre > best_by_channel[ch_name].snre:
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

    result = {
        "generated_utc": ts,
        "root": root,
        "num_runs": len(runs),
        "recursive_runs": recursive_runs,
        "base_results_json": base_results_json,
        "min_downsampled": min_downsampled,
        "disallow_brickwall_filters": disallow_brickwall_filters,
        "redownsample_after_trim": redownsample_after_trim,
        "classical_source": classical_source,
        "fixed_channel_configs": cfgs,
        "best_by_channel": {
            ch: {
                "run_index": c.run_index,
                "run_dir": c.run_dir,
                "run_relpath": c.run_relpath,
                "snre": c.snre,
                "margin_vs_classical": c.margin_vs_classical,
                "advantage_db": c.advantage_db,
                "trim_mode": c.trim_mode,
                "trim_points": c.trim_points,
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
        "beat_classical_indices": {ch: sorted(v) for ch, v in beat_classical.items()},
        "per_run": per_run,
    }

    os.makedirs(os.path.dirname(json_path), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    vprint(f"Wrote JSON: {json_path}")

    lines = []
    lines.append("# SNR Trim Optimization Report")
    lines.append("")
    lines.append(f"Generated (UTC): {ts}")
    lines.append(f"Runs processed: {len(runs)}")
    lines.append(f"Base fixed-config source: {base_results_json}")
    lines.append(f"Minimum downsampled retained points: {min_downsampled}")
    lines.append(f"Classical reference source: {classical_source}")
    lines.append("")
    lines.append("## Fixed Channel Configs (No Re-Sweep)")
    lines.append("")
    for ch in ("S1", "S2"):
        c = cfgs[ch]
        lines.append(
            f"- {ch}: filter=`{c['filter']}`, detrend=`{c['detrend']}`, clip=`{c['clip']}`, "
            f"threshold=`{c['threshold']}`, invert=`{fmt_bool(c['invert'])}`, metric=`{c['metric']}`, "
            f"M=`{c['M']}`, phase=`{c['phase']}`, lag=`{c['lag']}`"
        )
    lines.append("")

    lines.append("## Best Extracted SNR by Channel (With Trim Optimization)")
    lines.append("")
    lines.append("| Channel | Best Run Index | Max Extracted SNRe | Classical SNR_C (same run) | Margin | Advantage in dB | Trim | Retained Downsampled Points | Run Directory | Homodyne Path | Mod Path |")
    lines.append("|---|---:|---:|---:|---:|---:|---|---:|---|---|---|")
    for ch in ("S1", "S2"):
        b = best_by_channel.get(ch)
        if not b:
            lines.append(f"| {ch} | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |")
            continue
        homo_path = os.path.join(b.run_dir, b.homo_file) if b.homo_file else "n/a"
        mod_path = os.path.join(b.run_dir, b.mod_file) if b.mod_file else "n/a"
        lines.append(
            f"| {ch} | {b.run_index} | {b.snre:.6f} | {b.snre - b.margin_vs_classical:.6f} | "
            f"{b.margin_vs_classical:+.6f} | {b.advantage_db:+.6f} | {b.trim_mode}:{b.trim_points} | {b.n_points} | "
            f"`{b.run_dir}` | `{homo_path}` | `{mod_path}` |"
        )

    lines.append("")
    lines.append("## Classical-Limit Flags")
    lines.append("")
    for ch in ("S1", "S2"):
        flagged = sorted(beat_classical.get(ch, []))
        if flagged:
            lines.append(f"- {ch}: beats classical limit at run indices {', '.join(str(x) for x in flagged)}")
        else:
            lines.append(f"- {ch}: no run exceeded classical SNR_C under fixed-config trim optimization")

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- Filter/processing parameter space was not re-swept; per-channel settings were frozen from the provided base sweep JSON.")
    lines.append("- Only trim mode (`none`, `trim_start`, `trim_end`) and trim amount were optimized per run/channel.")
    lines.append("- Trim optimization retained at least the requested minimum number of downsampled points.")
    lines.append(f"- Re-downsample after trim: `{redownsample_after_trim}`.")
    lines.append(f"- Brick-wall filters disallowed: `{disallow_brickwall_filters}`.")
    lines.append("- `Advantage in dB` is computed as `10*log10(SNRe/SNR_C)`.")
    lines.append("- Channel mapping used: S1 homodyne `scope_*_2.csv` with modulation `scope_*_1.csv`; S2 homodyne `scope_*_3.csv` with modulation `scope_*_4.csv`.")
    lines.append(f"- Run discovery mode: `{'recursive' if recursive_runs else 'single-level'}`.")

    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    vprint(f"Wrote report: {report_path}")
    vprint("Trim optimization complete.")


if __name__ == "__main__":
    main()
