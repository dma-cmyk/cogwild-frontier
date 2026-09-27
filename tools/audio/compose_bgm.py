#!/usr/bin/env python3
"""Create five sample-aligned, loopable frontier-fantasy BGM tracks (numpy + ffmpeg)."""
from __future__ import annotations

import argparse
import math
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
# id, bpm, key midi, mode offsets, progression degrees, style
TRACKS = {
    "title": (104, 60, (0, 2, 4, 5, 7, 9, 11), (0, 4, 5, 3), "overture"),
    "frontier_day": (112, 62, (0, 2, 4, 5, 7, 9, 11), (0, 4, 5, 3), "pastoral"),
    "workshop": (120, 57, (0, 2, 4, 5, 7, 9, 11), (0, 5, 3, 4), "light"),
    "night": (78, 57, (0, 2, 3, 5, 7, 8, 10), (0, 5, 3, 6), "quiet"),
    "battle": (138, 57, (0, 2, 3, 5, 7, 8, 10), (0, 5, 6, 4), "drive"),
}


def midi(n: int) -> float:
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def note(out: np.ndarray, start: int, dur: int, hz: float, amp: float, kind: str, release: float = .12) -> None:
    count = min(len(out) - start, dur + int(release * SR))
    if count <= 0:
        return
    t = np.arange(count, dtype=np.float64) / SR
    sustain = min(dur, count)
    env = np.ones(count)
    attack = min(int(.012 * SR), sustain)
    if attack:
        env[:attack] = np.linspace(0, 1, attack, endpoint=False)
    env[sustain:] = np.linspace(1, 0, count - sustain, endpoint=False) if count > sustain else 1
    phase = 2 * np.pi * hz * t
    if kind == "pluck":
        sig = np.sin(phase) + .25 * np.sin(2 * phase) + .08 * np.sin(3 * phase)
        env *= np.exp(-t * 5.0)
    elif kind == "flute":
        sig = np.sin(phase) + .18 * np.sin(2 * phase) + .035 * np.sin(3 * phase)
        env *= np.minimum(1.0, t / .12)
    elif kind == "bell":
        sig = np.sin(phase) + .32 * np.sin(phase * 2.71) + .12 * np.sin(phase * 5.13)
        env *= np.exp(-t * 3.2)
    elif kind == "bass":
        sig = np.sin(phase) + .12 * np.sin(phase * 2)
    else:  # warm, lightly detuned pad
        sig = .7 * np.sin(phase) + .3 * np.sin(phase * 1.006)
        env *= np.minimum(1.0, t / .28)
    out[start:start + count] += (sig * env * amp).astype(np.float32)


def render(track_id: str, data: tuple) -> np.ndarray:
    bpm, root, scale, degrees, style = data
    bars, beats = 36, 4
    beat_samples = int(round(SR * 60 / bpm))
    bar_samples = beat_samples * beats
    length = bar_samples * bars
    out = np.zeros(length, dtype=np.float32)
    rng = np.random.default_rng(8821 + list(TRACKS).index(track_id) * 137)
    chords = []
    for d in degrees:
        chord = [root + scale[(d + x) % 7] + 12 * ((d + x) // 7) for x in (0, 2, 4)]
        chords.append(chord)
    for bar in range(bars):
        start = bar * bar_samples
        chord = chords[bar % len(chords)]
        if style in ("overture", "pastoral", "quiet"):
            for n in chord:
                note(out, start, bar_samples, midi(n + 12), .035 if style == "quiet" else .045, "pad", .1)
        else:
            for n in chord:
                note(out, start, int(bar_samples * .94), midi(n + 12), .027, "pad", .05)
        # Bass pulse: steady walking line, softer for night.
        for beat in range(4):
            bass_note = chord[0] - 12 if beat in (0, 2) else chord[1] - 12
            amp = .105 if style == "drive" else (.047 if style == "quiet" else .075)
            note(out, start + beat * beat_samples, int(beat_samples * .76), midi(bass_note), amp, "bass", .04)
        # An original 2-bar melody motif, varied by chord and phrase; rests retain breathing room.
        phrase = bar % 4
        melody_pattern = ((0, 2, 1, 2, 4, 2, 1, 0), (2, 4, 5, 4, 2, 1, 2, 4),
                          (4, 2, 1, 0, 2, 4, 2, 1), (0, 1, 2, 4, 2, 1, 0, 2))
        beat_slots = (0, .5, 1.5, 2, 3)
        if style == "quiet":
            beat_slots = (0, 1.5, 3)
        for i, beat in enumerate(beat_slots):
            degree = melody_pattern[phrase][((bar % 2) * 4 + i) % 8] % 7
            pitch = root + scale[degree] + 12
            # Bring melody close to current chord tones and avoid monotonous scalar runs.
            if i in (0, len(beat_slots) - 1):
                pitch = min((n + 12 for n in chord), key=lambda n: abs(n - pitch))
            at = start + int(beat * beat_samples)
            dur = int((.34 if style == "drive" else .42) * beat_samples)
            kind = "bell" if style in ("workshop", "night") and i in (0, 3) else ("flute" if style in ("overture", "pastoral", "quiet") else "pluck")
            amp = .095 if style == "drive" else (.045 if style == "quiet" else .073)
            note(out, at, dur, midi(pitch), amp, kind, .16)
        # Bright arpeggiated plucks make the light workshop groove distinct.
        if style in ("light", "overture"):
            for step in range(8):
                pitch = chord[(step + bar) % 3] + 24
                at = start + step * beat_samples // 2
                note(out, at, int(beat_samples * .28), midi(pitch), .035 if style == "light" else .022, "pluck", .07)
        # Percussion with genre-specific weight. Deterministic noise supports a clean repeated loop.
        if style in ("light", "pastoral", "drive"):
            for beat in range(4):
                at = start + beat * beat_samples
                kick_amp = .12 if style == "drive" else .055
                phase_t = np.arange(int(.18 * SR), dtype=np.float64) / SR
                kick = np.sin(2 * np.pi * (58 - 20 * phase_t) * phase_t) * np.exp(-phase_t * 18) * kick_amp
                end = min(length, at + len(kick)); out[at:end] += kick[:end-at].astype(np.float32)
                if beat in (1, 3) and style == "drive":
                    noise = rng.normal(0, 1, int(.11 * SR)) * np.exp(-np.arange(int(.11 * SR)) / SR * 34) * .045
                    end = min(length, at + len(noise)); out[at:end] += noise[:end-at].astype(np.float32)
                elif style == "light" and beat in (1, 3):
                    # Tiny brushed shaker.
                    noise = rng.normal(0, .013, int(.025 * SR))
                    end = min(length, at + len(noise)); out[at:end] += noise[:end-at].astype(np.float32)
        elif style == "overture" and bar % 4 == 0:
            # Gentle timpani-like low pulse, only at phrase turns.
            at = start
            t = np.arange(int(.24 * SR)) / SR
            pulse = .07 * np.sin(2*np.pi*(52-12*t)*t)*np.exp(-t*13)
            out[at:at+len(pulse)] += pulse.astype(np.float32)
    # Crossfade the tail into the post-head continuation so the loop boundary has matching phase.
    fade = min(int(.08 * SR), length // 8)
    original = out.copy()
    out[:-fade] = original[fade:]
    theta = np.linspace(0.0, np.pi / 2.0, fade, endpoint=False, dtype=np.float32)
    out[-fade:] = original[-fade:] * np.cos(theta) + original[fade:2 * fade] * np.sin(theta)
    # Target approximately -15.5 integrated RMS with safe peak reserve.
    rms = float(np.sqrt(np.mean(out.astype(np.float64) ** 2)))
    out *= 0.167 / max(rms, 1e-9)
    peak = float(np.max(np.abs(out)))
    if peak > .84:
        out *= .84 / peak
    return out


def encode(track_id: str, data: tuple, out_dir: Path) -> None:
    samples = render(track_id, data)
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", dir=out_dir, delete=False) as f:
        wav_path = Path(f.name)
    pcm = np.clip(samples, -1, 1)
    with wave.open(str(wav_path), "wb") as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(SR)
        wav.writeframes((pcm * 32767).astype("<i2").tobytes())
    try:
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "4", str(out_dir / f"bgm_{track_id}.ogg")], check=True)
    finally:
        wav_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "game/assets/audio")
    args = parser.parse_args()
    for ident, data in TRACKS.items():
        encode(ident, data, args.out)
        print(f"wrote bgm_{ident}.ogg ({36 * 4 * 60 / data[0]:.2f}s, sample-aligned loop)")


if __name__ == "__main__":
    main()
