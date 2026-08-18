#!/usr/bin/env python3
"""Synthesize TASK-010 placeholder WAVs (PT-style tones/noise).

Outputs 48 kHz / 16-bit / mono PCM under assets/sfx/v1/.
Normalises to -16 LUFS (ITU-R BS.1770-4 K-weight, ungated) except
emg_alert at -12 LUFS. Loop beds are equal-power crossfaded so wrap
is seamless. Deterministic (seeded) so re-runs stay bit-stable.

Commissioned recordings (KRX-020) replace these files in place.
"""

from __future__ import annotations

import math
import os
import random
import struct
import sys
import wave

SR = 48000
TARGET_LUFS = -16.0
EMERGENCY_LUFS = -12.0
PEAK_CEILING = 0.99

# BS.1770-4 K-weighting biquads at 48 kHz (pre-filter + RLB).
PRE_B = (1.53512485958697, -2.69169618940638, 1.19839281085285)
PRE_A = (1.0, -1.69065929318241, 0.73248077421585)
RLB_B = (1.0, -2.0, 1.0)
RLB_A = (1.0, -1.99004745483398, 0.99007225036621)


def _biquad(xs: list[float], b: tuple[float, ...], a: tuple[float, ...]) -> list[float]:
    y: list[float] = [0.0] * len(xs)
    x1 = x2 = y1 = y2 = 0.0
    for i, xn in enumerate(xs):
        yn = b[0] * xn + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        y[i] = yn
        x2, x1 = x1, xn
        y2, y1 = y1, yn
    return y


def integrated_lufs(xs: list[float]) -> float:
    if not xs:
        return float("-inf")
    k = _biquad(_biquad(xs, PRE_B, PRE_A), RLB_B, RLB_A)
    ms = sum(s * s for s in k) / len(k)
    if ms <= 1e-20:
        return float("-inf")
    return -0.691 + 10.0 * math.log10(ms)


def normalize_lufs(xs: list[float], target: float) -> list[float]:
    measured = integrated_lufs(xs)
    if measured == float("-inf"):
        return list(xs)
    gain = 10.0 ** ((target - measured) / 20.0)
    out = [s * gain for s in xs]
    peak = max((abs(s) for s in out), default=0.0)
    if peak > PEAK_CEILING:
        scale = PEAK_CEILING / peak
        out = [s * scale for s in out]
    return out


def write_wav(path: str, xs: list[float], target: float) -> float:
    xs = normalize_lufs(xs, target)
    measured = integrated_lufs(xs)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        frames = bytearray()
        for s in xs:
            v = max(-1.0, min(1.0, s))
            frames.extend(struct.pack("<h", int(round(v * 32767.0))))
        wf.writeframes(bytes(frames))
    return measured


def n_samples(ms: float) -> int:
    return max(1, int(round(SR * ms / 1000.0)))


def adsr(n: int, attack_ms: float, release_ms: float) -> list[float]:
    a = min(n, n_samples(attack_ms))
    r = min(n, n_samples(release_ms))
    env = [1.0] * n
    if a > 1:
        for i in range(a):
            env[i] = i / (a - 1)
    elif a == 1:
        env[0] = 1.0
    if r > 1:
        for i in range(r):
            env[n - r + i] = 1.0 - i / (r - 1)
    elif r == 1:
        env[-1] = 0.0
    return env


def apply_env(xs: list[float], attack_ms: float, release_ms: float) -> list[float]:
    env = adsr(len(xs), attack_ms, release_ms)
    return [x * e for x, e in zip(xs, env)]


def mix_at(dst: list[float], src: list[float], offset: int, gain: float = 1.0) -> None:
    for i, s in enumerate(src):
        j = offset + i
        if 0 <= j < len(dst):
            dst[j] += s * gain


def osc(freq: float, ms: float, kind: str = "sine") -> list[float]:
    n = n_samples(ms)
    out = [0.0] * n
    for i in range(n):
        p = (i * freq / SR) % 1.0
        if kind == "sine":
            out[i] = math.sin(2.0 * math.pi * p)
        elif kind == "square":
            out[i] = 1.0 if p < 0.5 else -1.0
        elif kind == "saw":
            out[i] = 2.0 * p - 1.0
        else:
            raise ValueError(kind)
    return out


def noise(ms: float, rng: random.Random) -> list[float]:
    return [rng.uniform(-1.0, 1.0) for _ in range(n_samples(ms))]


def bandpass(xs: list[float], freq: float, q: float) -> list[float]:
    # RBJ peaking-as-bandpass via constant-skirt BPF.
    w0 = 2.0 * math.pi * freq / SR
    alpha = math.sin(w0) / (2.0 * q)
    b0 = alpha
    b1 = 0.0
    b2 = -alpha
    a0 = 1.0 + alpha
    a1 = -2.0 * math.cos(w0)
    a2 = 1.0 - alpha
    return _biquad(xs, (b0 / a0, b1 / a0, b2 / a0), (1.0, a1 / a0, a2 / a0))


def noise_burst(ms: float, freq: float, q: float, rng: random.Random) -> list[float]:
    return apply_env(bandpass(noise(ms, rng), freq, q), 2.0, max(8.0, ms * 0.7))


def seamless_loop(xs: list[float], fade_ms: float = 20.0) -> list[float]:
    n = n_samples(fade_ms)
    if n <= 0 or n * 2 >= len(xs):
        return xs
    head = xs[:n]
    tail = xs[-n:]
    faded = [
        head[i] * (i / n) + tail[i] * (1.0 - i / n) for i in range(n)
    ]
    return faded + xs[n:-n]


def make_bed(ms: float, freq: float, q: float, rng: random.Random) -> list[float]:
    fade_ms = 20.0
    raw = bandpass(noise(ms + fade_ms, rng), freq, q)
    looped = seamless_loop(raw, fade_ms=fade_ms)
    want = n_samples(ms)
    if len(looped) > want:
        return looped[:want]
    if len(looped) < want:
        return looped + [0.0] * (want - len(looped))
    return looped


def build_all(out_dir: str) -> dict[str, float]:
    rng = random.Random(0x4B455258)  # 'KERX'
    measured: dict[str, float] = {}

    def emit(name: str, xs: list[float], target: float = TARGET_LUFS) -> None:
        path = os.path.join(out_dir, f"{name}.wav")
        measured[name] = write_wav(path, xs, target)

    emit("squelch_open", noise_burst(60, 3000, 0.6, rng))
    emit("squelch_tail", noise_burst(70, 2400, 0.55, rng))
    emit("static_bed_1", make_bed(2000, 2500, 0.8, rng))
    emit("static_bed_2", make_bed(2000, 1800, 0.7, rng))
    emit("static_bed_3", make_bed(2000, 1200, 0.5, rng))
    emit("tune_burst", noise_burst(300, 2200, 0.6, rng))
    emit("scan_tick", noise_burst(25, 4200, 0.8, rng))

    emit("roger_k", apply_env(osc(1180, 90, "square"), 6, 20))
    dual = [0.0] * n_samples(180)
    mix_at(dual, apply_env(osc(980, 80, "sine"), 6, 18), 0)
    mix_at(dual, apply_env(osc(1310, 80, "sine"), 6, 18), n_samples(90))
    emit("roger_dual", dual)
    moto = [0.0] * n_samples(200)
    for i, f in enumerate((1800, 1400, 1800)):
        mix_at(moto, apply_env(osc(f, 40, "square"), 4, 10), n_samples(i * 65))
    emit("roger_moto", moto)

    deny = [0.0] * n_samples(200)
    mix_at(deny, apply_env(osc(180, 90, "saw"), 4, 20), 0)
    mix_at(deny, apply_env(osc(150, 90, "saw"), 4, 20), n_samples(110))
    emit("deny_buzz", deny)

    tot_warn = [0.0] * n_samples(180)
    mix_at(tot_warn, apply_env(osc(1400, 50, "square"), 3, 8), 0)
    mix_at(tot_warn, apply_env(osc(1400, 50, "square"), 3, 8), n_samples(120))
    emit("tot_warn", tot_warn)
    emit("tot_cut", apply_env(osc(220, 250, "saw"), 4, 40))

    lost = [0.0] * n_samples(200)
    mix_at(lost, apply_env(osc(780, 70, "sine"), 5, 15), 0)
    mix_at(lost, apply_env(osc(430, 90, "sine"), 5, 20), n_samples(90))
    emit("link_lost", lost)
    up = [0.0] * n_samples(160)
    mix_at(up, apply_env(osc(640, 60, "sine"), 5, 12), 0)
    mix_at(up, apply_env(osc(960, 80, "sine"), 5, 16), n_samples(70))
    emit("link_up", up)

    emg = [0.0] * n_samples(900)
    for i in range(4):
        t0 = n_samples(i * 220)
        mix_at(emg, apply_env(osc(1600, 100, "square"), 4, 12), t0)
        mix_at(emg, apply_env(osc(1100, 100, "square"), 4, 12), t0 + n_samples(100))
    emit("emg_alert", emg, EMERGENCY_LUFS)

    emit("rchk_ok", apply_env(osc(880, 120, "sine"), 6, 24))
    emit("key_click", noise_burst(18, 3500, 1.1, rng))
    emit("knob_tick", noise_burst(8, 4200, 1.2, rng))
    emit("slider_thunk", apply_env(osc(90, 30, "sine"), 2, 16))

    power_on = [0.0] * n_samples(280)
    mix_at(power_on, apply_env(osc(520, 70, "sine"), 6, 12), 0)
    mix_at(power_on, apply_env(osc(780, 70, "sine"), 6, 12), n_samples(70))
    mix_at(power_on, apply_env(osc(1040, 110, "sine"), 6, 20), n_samples(140))
    emit("power_on", power_on)

    power_off = [0.0] * n_samples(220)
    mix_at(power_off, apply_env(osc(780, 70, "sine"), 6, 12), 0)
    mix_at(power_off, apply_env(osc(430, 130, "sine"), 6, 24), n_samples(70))
    emit("power_off", power_off)

    return measured


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.normpath(os.path.join(here, "..", "v1"))
    measured = build_all(out_dir)
    for name, lufs in sorted(measured.items()):
        print(f"{name:16s}  {lufs:7.2f} LUFS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
