#!/usr/bin/env python3
"""
Conductor text-director model: corpus-aware training pipeline.

What this script now does:
1) Generates synthetic baseline training data (existing behavior).
2) Optionally trains on your real strict/loose script banks.
3) Optionally augments corpus lines using OpenAI as a semantic teacher.
4) Exports both runtime targets:
   - CoreML bundle: ConductorTextDirector.mlmodelc
   - Backend model: ConductorTextDirector.backend.json

Usage examples:
  # baseline synthetic
  python train_conductor_model.py --samples 20000 --epochs 250

  # corpus-aware training
  python train_conductor_model.py \
    --samples 12000 \
    --corpus-samples 16000 \
    --strict-bank /path/to/strict.txt \
    --loose-bank /path/to/loose.txt \
    --epochs 250

  # corpus + OpenAI semantic augmentation
  python train_conductor_model.py \
    --samples 12000 \
    --corpus-samples 18000 \
    --strict-bank /path/to/strict.txt \
    --loose-bank /path/to/loose.txt \
    --semantic-teacher openai \
    --semantic-augment-lines 250 \
    --semantic-model gpt-4.1-mini \
    --semantic-api-key "$OPENAI_API_KEY"
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import torch
import torch.nn as nn
from sklearn.linear_model import LinearRegression
from torch.utils.data import DataLoader, TensorDataset

# ---------------------------------------------------------------------------
# 1. Data model + constants
# ---------------------------------------------------------------------------

INPUT_NAMES = [
    "weight",
    "arc",
    "textLength",
    "textAmount",
    "compositeBias",
    "audioGain",
    "spatialX",
    "spatialY",
    "spatialZ",
    "isMain",
    "audioRMS",
    "audioSpectralCentroid",
    "videoLuminance",
    "videoMotion",
]

OUTPUT_NAMES = [
    "score",
    "displayDuration",
    "compositeAlpha",
    "fontSize",
    "fontWeight",
]

BANNED_TEXT_PATTERNS = [
    re.compile(r"\bjourney\b", re.IGNORECASE),
    re.compile(r"\bgrowth\b", re.IGNORECASE),
    re.compile(r"\bhealing\b", re.IGNORECASE),
    re.compile(r"\btherapy\b", re.IGNORECASE),
    re.compile(r"\btrauma\b", re.IGNORECASE),
    re.compile(r"\btranscend", re.IGNORECASE),
    re.compile(r"\bsavior\b", re.IGNORECASE),
]


@dataclass(frozen=True)
class CorpusCandidate:
    text: str
    weight: float
    bank: str  # strict | loose | semantic-strict | semantic-loose
    source_id: str | None = None


def clamp(value: float, min_value: float, max_value: float) -> float:
    return max(min_value, min(max_value, value))


def sanitize_text(value: str) -> str:
    line = value.replace("\u200b", " ").replace("\u00a0", " ")
    line = re.sub(r"\s+", " ", line)
    line = re.sub(r"\s+([,.;!?])", r"\1", line)
    return line.strip()


def passes_guardrails(text: str) -> bool:
    if len(text) < 10 or len(text) > 280:
        return False
    return not any(pattern.search(text) for pattern in BANNED_TEXT_PATTERNS)


# ---------------------------------------------------------------------------
# 2. Script bank loading
# ---------------------------------------------------------------------------


def parse_weight(value: Any, default: float = 0.7) -> float:
    if isinstance(value, (int, float)) and np.isfinite(value):
        return clamp(float(value), 0.0, 1.0)
    if isinstance(value, str):
        try:
            return clamp(float(value.strip()), 0.0, 1.0)
        except ValueError:
            return default
    return default


def parse_delimited_line(line: str) -> tuple[str | None, float | None, str]:
    parts = [segment.strip() for segment in line.split("|")]
    if len(parts) == 1:
        return None, None, parts[0]
    if len(parts) >= 3:
        candidate_id = parts[0] if parts[0] else None
        weight = parse_weight(parts[1], default=0.7)
        text = "|".join(parts[2:]).strip()
        return candidate_id, weight, text
    maybe_weight = parts[0]
    text = parts[1]
    try:
        weight = clamp(float(maybe_weight), 0.0, 1.0)
        return None, weight, text
    except ValueError:
        return maybe_weight if maybe_weight else None, None, text


def parse_candidate_entry(value: Any, bank: str, index: int) -> CorpusCandidate | None:
    if isinstance(value, str):
        text = sanitize_text(value)
        if not passes_guardrails(text):
            return None
        return CorpusCandidate(text=text, weight=0.7, bank=bank, source_id=f"{bank}-{index + 1}")

    if not isinstance(value, dict):
        return None

    text_value = value.get("text") or value.get("line") or value.get("baseText") or value.get("content")
    if not isinstance(text_value, str):
        return None
    text = sanitize_text(text_value)
    if not passes_guardrails(text):
        return None

    source_id = value.get("id")
    candidate_id = str(source_id).strip() if source_id is not None else f"{bank}-{index + 1}"
    if candidate_id == "":
        candidate_id = f"{bank}-{index + 1}"

    return CorpusCandidate(
        text=text,
        weight=parse_weight(value.get("weight"), default=0.7),
        bank=bank,
        source_id=candidate_id,
    )


def extract_candidate_source(decoded: Any, bank_hint: str) -> list[Any]:
    if isinstance(decoded, list):
        return decoded
    if not isinstance(decoded, dict):
        return []

    if bank_hint in decoded and isinstance(decoded[bank_hint], list):
        return decoded[bank_hint]

    for key in ("candidates", "lines", "entries"):
        value = decoded.get(key)
        if isinstance(value, list):
            return value

    return []


def parse_bank_text(raw: str, bank_hint: str) -> list[CorpusCandidate]:
    parsed: list[CorpusCandidate] = []
    seen: set[str] = set()
    for line in raw.splitlines():
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("#") or trimmed.startswith("//"):
            continue
        candidate_id, weight, text = parse_delimited_line(trimmed)
        sanitized = sanitize_text(text)
        if not passes_guardrails(sanitized):
            continue
        key = sanitized.lower()
        if key in seen:
            continue
        seen.add(key)
        parsed.append(
            CorpusCandidate(
                text=sanitized,
                weight=clamp(weight if weight is not None else 0.7, 0.0, 1.0),
                bank=bank_hint,
                source_id=candidate_id or f"{bank_hint}-{len(parsed) + 1}",
            )
        )
    return parsed


def load_bank_file(path: Path, bank_hint: str) -> list[CorpusCandidate]:
    if not path.exists():
        raise FileNotFoundError(f"bank path does not exist: {path}")
    raw = path.read_text(encoding="utf-8")
    trimmed = raw.strip()
    if not trimmed:
        return []

    if trimmed.startswith("{") or trimmed.startswith("["):
        try:
            decoded = json.loads(trimmed)
            source = extract_candidate_source(decoded, bank_hint)
            parsed = [
                candidate
                for index, entry in enumerate(source)
                if (candidate := parse_candidate_entry(entry, bank_hint, index)) is not None
            ]
            if parsed:
                return dedupe_candidates(parsed)
        except json.JSONDecodeError:
            # fall through to text parser below
            pass

    return dedupe_candidates(parse_bank_text(raw, bank_hint))


def load_corpus_candidates(
    combined_bank: Path | None,
    strict_bank: Path | None,
    loose_bank: Path | None,
) -> tuple[list[CorpusCandidate], dict[str, int]]:
    candidates: list[CorpusCandidate] = []

    if combined_bank:
        combined_raw = combined_bank.read_text(encoding="utf-8").strip()
        if combined_raw:
            decoded = json.loads(combined_raw)
            strict_source = extract_candidate_source(decoded, "strict")
            loose_source = extract_candidate_source(decoded, "loose")
            candidates.extend(
                candidate
                for index, entry in enumerate(strict_source)
                if (candidate := parse_candidate_entry(entry, "strict", index)) is not None
            )
            candidates.extend(
                candidate
                for index, entry in enumerate(loose_source)
                if (candidate := parse_candidate_entry(entry, "loose", index)) is not None
            )

    if strict_bank:
        candidates.extend(load_bank_file(strict_bank, "strict"))
    if loose_bank:
        candidates.extend(load_bank_file(loose_bank, "loose"))

    candidates = dedupe_candidates(candidates)
    stats: dict[str, int] = {}
    for candidate in candidates:
        stats[candidate.bank] = stats.get(candidate.bank, 0) + 1
    return candidates, stats


def dedupe_candidates(candidates: list[CorpusCandidate]) -> list[CorpusCandidate]:
    deduped: list[CorpusCandidate] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = candidate.text.lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(candidate)
    return deduped


# ---------------------------------------------------------------------------
# 3. Optional semantic teacher augmentation (OpenAI)
# ---------------------------------------------------------------------------


def extract_assistant_content(payload: dict[str, Any]) -> str | None:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return None
    first = choices[0]
    if not isinstance(first, dict):
        return None
    message = first.get("message")
    if not isinstance(message, dict):
        return None
    content = message.get("content")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        chunks: list[str] = []
        for chunk in content:
            if isinstance(chunk, str):
                chunks.append(chunk)
            elif isinstance(chunk, dict) and isinstance(chunk.get("text"), str):
                chunks.append(chunk["text"])
        joined = "\n".join(chunks).strip()
        return joined if joined else None
    return None


def openai_semantic_augment(
    corpus: list[CorpusCandidate],
    count: int,
    model: str,
    api_key: str | None,
    seed: int,
) -> list[CorpusCandidate]:
    if count <= 0:
        return []
    if not api_key:
        print("  semantic-teacher requested but no API key supplied; skipping augmentation.")
        return []
    if not corpus:
        print("  semantic-teacher requested but no corpus lines are loaded; skipping augmentation.")
        return []

    rng = np.random.default_rng(seed + 97)
    strict_examples = [entry.text for entry in corpus if "strict" in entry.bank][:8]
    loose_examples = [entry.text for entry in corpus if "loose" in entry.bank][:8]
    if not strict_examples:
        strict_examples = [entry.text for entry in corpus[:8]]
    if not loose_examples:
        loose_examples = [entry.text for entry in corpus[-8:]]

    prompt = "\n".join(
        [
            "Generate additional script lines for a live cinematic text system.",
            "Return JSON only in this shape:",
            '{"candidates":[{"text":"...", "weight":0.0, "bank":"strict|loose"}]}',
            "",
            f"Generate {count} candidates total.",
            "Constraints:",
            "- first-person, intimate, uncanny, concise",
            "- no journey/growth/therapy/trauma/transcendence/savior/tech-hype language",
            "- each line 12..180 characters",
            "",
            "Strict examples:",
            *[f"- {line}" for line in strict_examples],
            "",
            "Loose examples:",
            *[f"- {line}" for line in loose_examples],
        ]
    )
    payload = {
        "model": model,
        "temperature": 0.7,
        "response_format": {"type": "json_object"},
        "messages": [
            {
                "role": "system",
                "content": "You generate cinematic text candidates. Return valid JSON only.",
            },
            {"role": "user", "content": prompt},
        ],
    }

    request = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=18) as response:
            raw = response.read().decode("utf-8")
            decoded = json.loads(raw)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        print(f"  semantic teacher HTTP error {exc.code}: {body[:240]}")
        return []
    except Exception as exc:
        print(f"  semantic teacher request failed: {exc}")
        return []

    content = extract_assistant_content(decoded)
    if not content:
        print("  semantic teacher response missing assistant content; skipping augmentation.")
        return []

    try:
        structured = json.loads(content)
    except json.JSONDecodeError:
        print("  semantic teacher returned non-JSON assistant content; skipping augmentation.")
        return []

    source = structured.get("candidates") if isinstance(structured, dict) else None
    if not isinstance(source, list):
        print("  semantic teacher returned no candidates array; skipping augmentation.")
        return []

    augmented: list[CorpusCandidate] = []
    for index, entry in enumerate(source):
        if not isinstance(entry, dict):
            continue
        text = sanitize_text(str(entry.get("text", "")))
        if not passes_guardrails(text):
            continue
        bank = str(entry.get("bank", "loose")).strip().lower()
        if bank not in ("strict", "loose"):
            bank = "loose"
        augmented.append(
            CorpusCandidate(
                text=text,
                weight=parse_weight(entry.get("weight"), default=0.68),
                bank=f"semantic-{bank}",
                source_id=f"sem-{index + 1}",
            )
        )

    # deterministic subsample if model returned too many
    if len(augmented) > count:
        indexes = rng.choice(len(augmented), size=count, replace=False)
        augmented = [augmented[int(i)] for i in sorted(indexes.tolist())]

    augmented = dedupe_candidates(augmented)
    print(f"  semantic teacher produced {len(augmented)} usable candidate(s).")
    return augmented


# ---------------------------------------------------------------------------
# 4. Dataset generation
# ---------------------------------------------------------------------------


def generate_synthetic_data(n: int, seed: int = 42) -> tuple[np.ndarray, np.ndarray]:
    """Return baseline synthetic (X, Y) arrays shaped (n, 14) and (n, 5)."""
    rng = np.random.default_rng(seed)

    weight = rng.uniform(0.0, 1.0, n)
    arc = rng.choice([1.0, 2.0, 3.0], n)
    text_length = rng.uniform(0.0, 1.0, n)
    text_amount = rng.uniform(0.0, 1.0, n)
    composite_bias = rng.uniform(0.0, 1.0, n)
    audio_gain = rng.uniform(0.0, 1.0, n)
    spatial_x = rng.uniform(0.0, 1.0, n)
    spatial_y = rng.uniform(0.0, 1.0, n)
    spatial_z = rng.uniform(0.0, 1.0, n)
    is_main = rng.choice([0.0, 1.0], n)
    audio_rms = rng.uniform(0.0, 1.0, n)
    audio_spectral = rng.uniform(0.0, 1.0, n)
    video_lum = rng.uniform(0.0, 1.0, n)
    video_motion = rng.uniform(0.0, 1.0, n)

    score = weight + text_amount * 0.25 + composite_bias * 0.15 + is_main * 0.20
    score += audio_rms * 0.10 + video_motion * 0.05
    score = np.clip(score, 0.0, 2.0) / 2.0

    display_duration = 3.0 + text_length * 7.0 + text_amount * 3.0
    display_duration -= audio_rms * 2.0
    display_duration += (1.0 - video_motion) * 1.5
    display_duration = np.clip(display_duration, 1.0, 15.0)

    composite_alpha = composite_bias * 0.55 + 0.35 + audio_gain * 0.10
    composite_alpha = np.clip(composite_alpha, 0.2, 1.0)

    font_size = text_amount * 0.45 + 0.25 + audio_rms * 0.15 + video_lum * 0.10
    font_size = np.clip(font_size, 0.15, 1.0)

    spatial_energy = np.sqrt(spatial_x**2 + spatial_y**2 + spatial_z**2) / np.sqrt(3.0)
    font_weight = composite_bias * 0.40 + 0.25 + spatial_energy * 0.20 + audio_rms * 0.15
    font_weight = np.clip(font_weight, 0.1, 1.0)

    noise_scale = 0.03
    score += rng.normal(0, noise_scale, n)
    display_duration += rng.normal(0, noise_scale * 10, n)
    composite_alpha += rng.normal(0, noise_scale, n)
    font_size += rng.normal(0, noise_scale, n)
    font_weight += rng.normal(0, noise_scale, n)

    score = np.clip(score, 0.0, 1.0)
    display_duration = np.clip(display_duration, 1.0, 15.0)
    composite_alpha = np.clip(composite_alpha, 0.0, 1.0)
    font_size = np.clip(font_size, 0.0, 1.0)
    font_weight = np.clip(font_weight, 0.0, 1.0)

    X = np.column_stack(
        [
            weight,
            arc,
            text_length,
            text_amount,
            composite_bias,
            audio_gain,
            spatial_x,
            spatial_y,
            spatial_z,
            is_main,
            audio_rms,
            audio_spectral,
            video_lum,
            video_motion,
        ]
    )
    Y = np.column_stack([score, display_duration, composite_alpha, font_size, font_weight])
    return X.astype(np.float32), Y.astype(np.float32)


def lexical_profile(text: str) -> dict[str, float]:
    tokens = re.findall(r"[A-Za-z']+", text.lower())
    token_count = max(1, len(tokens))
    first_person = sum(1 for token in tokens if token in {"i", "me", "my", "mine", "we", "our", "us"}) / token_count
    punctuation_count = sum(1 for ch in text if ch in ".,;:!?")
    energy = clamp(punctuation_count / max(8, len(text)) * 6.0, 0.0, 1.0)
    has_question = 1.0 if "?" in text else 0.0
    has_exclamation = 1.0 if "!" in text else 0.0
    avg_word_length = sum(len(token) for token in tokens) / token_count
    imperative_hint = 1.0 if tokens and tokens[0] in {"cut", "hold", "split", "echo", "withhold", "stretch", "listen"} else 0.0
    calmness = clamp(1.0 - energy * 0.9 - has_exclamation * 0.2, 0.0, 1.0)
    complexity = clamp((avg_word_length - 3.5) / 4.5, 0.0, 1.0)
    return {
        "first_person": first_person,
        "energy": energy,
        "question": has_question,
        "exclamation": has_exclamation,
        "imperative": imperative_hint,
        "calmness": calmness,
        "complexity": complexity,
    }


def generate_corpus_aligned_data(
    candidates: list[CorpusCandidate],
    n: int,
    seed: int = 42,
) -> tuple[np.ndarray, np.ndarray]:
    """Generate dataset grounded in real corpus lines."""
    if n <= 0 or not candidates:
        return np.empty((0, 14), dtype=np.float32), np.empty((0, 5), dtype=np.float32)

    rng = np.random.default_rng(seed + 17)
    sample_weights = np.array([max(0.05, candidate.weight) for candidate in candidates], dtype=np.float64)
    sample_weights = sample_weights / sample_weights.sum()
    picked_indexes = rng.choice(len(candidates), size=n, replace=True, p=sample_weights)

    X = np.zeros((n, len(INPUT_NAMES)), dtype=np.float32)
    Y = np.zeros((n, len(OUTPUT_NAMES)), dtype=np.float32)

    for row, candidate_index in enumerate(picked_indexes):
        candidate = candidates[int(candidate_index)]
        profile = lexical_profile(candidate.text)

        text_length = clamp(len(candidate.text) / 220.0, 0.0, 1.0)
        strictish = 1.0 if "strict" in candidate.bank else 0.0
        semanticish = 1.0 if candidate.bank.startswith("semantic-") else 0.0

        text_amount = float(rng.beta(2.6 if strictish else 2.1, 1.8 if strictish else 2.5))
        composite_bias = float(rng.beta(2.2, 2.2))
        audio_gain = float(rng.beta(2.0, 2.0))
        spatial_x = float(rng.uniform(0.0, 1.0))
        spatial_y = float(rng.uniform(0.0, 1.0))
        spatial_z = float(rng.uniform(0.0, 1.0))
        is_main = 1.0 if rng.uniform() < (0.62 if strictish else 0.48) else 0.0
        audio_rms = float(clamp(rng.normal(0.45 + profile["energy"] * 0.25, 0.18), 0.0, 1.0))
        audio_spectral = float(clamp(rng.normal(0.45 + profile["complexity"] * 0.22, 0.2), 0.0, 1.0))
        video_luminance = float(clamp(composite_bias * 0.62 + audio_gain * 0.30 + rng.normal(0.0, 0.08), 0.0, 1.0))
        video_motion = float(clamp(audio_rms * 0.55 + profile["energy"] * 0.35 + rng.normal(0.0, 0.1), 0.0, 1.0))
        arc = float(
            rng.choice(
                [1.0, 2.0, 3.0],
                p=[0.48, 0.42, 0.10] if strictish else [0.18, 0.56, 0.26],
            )
        )

        score = (
            candidate.weight * 0.58
            + text_amount * 0.16
            + composite_bias * 0.10
            + is_main * 0.09
            + profile["first_person"] * 0.09
            + profile["imperative"] * 0.06
            + audio_rms * 0.07
            + (0.05 if strictish else -0.02)
            + (0.02 if semanticish else 0.0)
        )
        if profile["question"] > 0:
            score += 0.03
        if profile["exclamation"] > 0:
            score += 0.02
        score = clamp(score + rng.normal(0.0, 0.025), 0.0, 1.0)

        display_duration = (
            2.4
            + text_length * 8.3
            + profile["calmness"] * 1.8
            + text_amount * 2.2
            - audio_rms * 1.7
            - profile["energy"] * 1.0
            + (0.7 if strictish else -0.1)
        )
        display_duration = clamp(display_duration + rng.normal(0.0, 0.35), 1.0, 15.0)

        composite_alpha = (
            0.24
            + composite_bias * 0.49
            + audio_gain * 0.13
            + profile["energy"] * 0.08
            - profile["question"] * 0.04
        )
        composite_alpha = clamp(composite_alpha + rng.normal(0.0, 0.03), 0.0, 1.0)

        font_size = (
            0.23
            + text_amount * 0.44
            + profile["complexity"] * 0.16
            + audio_rms * 0.12
            + (0.05 if strictish else -0.02)
        )
        font_size = clamp(font_size + rng.normal(0.0, 0.03), 0.0, 1.0)

        spatial_energy = math.sqrt(spatial_x**2 + spatial_y**2 + spatial_z**2) / math.sqrt(3.0)
        font_weight = (
            0.18
            + composite_bias * 0.35
            + spatial_energy * 0.18
            + profile["energy"] * 0.16
            + profile["imperative"] * 0.08
        )
        font_weight = clamp(font_weight + rng.normal(0.0, 0.03), 0.0, 1.0)

        X[row, :] = np.array(
            [
                clamp(candidate.weight, 0.0, 1.0),
                arc,
                text_length,
                text_amount,
                composite_bias,
                audio_gain,
                spatial_x,
                spatial_y,
                spatial_z,
                is_main,
                audio_rms,
                audio_spectral,
                video_luminance,
                video_motion,
            ],
            dtype=np.float32,
        )
        Y[row, :] = np.array(
            [score, display_duration, composite_alpha, font_size, font_weight],
            dtype=np.float32,
        )

    return X, Y


# ---------------------------------------------------------------------------
# 5. Model definition + training
# ---------------------------------------------------------------------------


class ConductorTextDirector(nn.Module):
    """Small MLP: 14 → 64 → 32 → 5 with residual shortcut."""

    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(14, 64)
        self.bn1 = nn.BatchNorm1d(64)
        self.fc2 = nn.Linear(64, 64)
        self.bn2 = nn.BatchNorm1d(64)
        self.fc3 = nn.Linear(64, 32)
        self.bn3 = nn.BatchNorm1d(32)
        self.head = nn.Linear(32, 5)
        self.act = nn.SiLU()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h = self.act(self.bn1(self.fc1(x)))
        h = self.act(self.bn2(self.fc2(h))) + h
        h = self.act(self.bn3(self.fc3(h)))
        return self.head(h)


def train(
    model: ConductorTextDirector,
    X: np.ndarray,
    Y: np.ndarray,
    epochs: int = 200,
    lr: float = 1e-3,
    batch_size: int = 256,
) -> list[float]:
    Xt = torch.from_numpy(X)
    Yt = torch.from_numpy(Y)
    dataset = TensorDataset(Xt, Yt)
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    output_weights = torch.tensor([2.0, 0.1, 1.0, 1.0, 1.0])
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    criterion = nn.MSELoss(reduction="none")

    losses: list[float] = []
    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        for xb, yb in loader:
            pred = model(xb)
            per_output = criterion(pred, yb).mean(dim=0)
            loss = (per_output * output_weights).sum()
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            epoch_loss += float(loss.item())
        scheduler.step()
        avg = epoch_loss / max(1, len(loader))
        losses.append(avg)
        if (epoch + 1) % 50 == 0 or epoch == 0:
            print(f"  epoch {epoch + 1:4d}/{epochs}  loss={avg:.5f}")
    return losses


# ---------------------------------------------------------------------------
# 6. CoreML conversion + backend export
# ---------------------------------------------------------------------------


class _ExportWrapper(nn.Module):
    """Wrapper with named scalar inputs for CoreML."""

    def __init__(self, core: ConductorTextDirector):
        super().__init__()
        self.core = core

    def forward(
        self,
        weight: torch.Tensor,
        arc: torch.Tensor,
        textLength: torch.Tensor,
        textAmount: torch.Tensor,
        compositeBias: torch.Tensor,
        audioGain: torch.Tensor,
        spatialX: torch.Tensor,
        spatialY: torch.Tensor,
        spatialZ: torch.Tensor,
        isMain: torch.Tensor,
        audioRMS: torch.Tensor,
        audioSpectralCentroid: torch.Tensor,
        videoLuminance: torch.Tensor,
        videoMotion: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        x = torch.cat(
            [
                weight,
                arc,
                textLength,
                textAmount,
                compositeBias,
                audioGain,
                spatialX,
                spatialY,
                spatialZ,
                isMain,
                audioRMS,
                audioSpectralCentroid,
                videoLuminance,
                videoMotion,
            ],
            dim=-1,
        ).unsqueeze(0)
        out = self.core(x).squeeze(0)
        return out[0:1], out[1:2], out[2:3], out[3:4], out[4:5]


def convert_to_coreml(
    model: ConductorTextDirector,
    output_dir: Path,
    model_name: str = "ConductorTextDirector",
) -> Path:
    import coremltools as ct

    model.eval()
    wrapper = _ExportWrapper(model)
    wrapper.eval()

    example_inputs = tuple(torch.tensor([0.5]) for _ in INPUT_NAMES)
    traced = torch.jit.trace(wrapper, example_inputs)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name=name, shape=(1,), dtype=np.float32) for name in INPUT_NAMES],
        outputs=[ct.TensorType(name=name) for name in OUTPUT_NAMES],
        minimum_deployment_target=ct.target.macOS14,
    )

    mlmodel.author = "ConductorHarness training pipeline"
    mlmodel.short_description = "Text-director model for selection + presentation style."
    mlmodel.version = "0.2.0"

    package_path = output_dir / f"{model_name}.mlpackage"
    mlmodel.save(str(package_path))
    print(f"  saved .mlpackage → {package_path}")

    compiled_path = output_dir / f"{model_name}.mlmodelc"
    if compiled_path.exists():
        shutil.rmtree(compiled_path)

    result = subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(package_path), str(output_dir)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"  xcrun coremlcompiler failed:\n{result.stderr}")
        print("  .mlpackage saved; compile manually in Xcode if needed.")
        return package_path

    print(f"  compiled .mlmodelc → {compiled_path}")
    return compiled_path


def export_backend_linear_model(
    X: np.ndarray,
    Y: np.ndarray,
    output_dir: Path,
    model_name: str = "ConductorTextDirector",
    metadata_extra: dict[str, Any] | None = None,
) -> Path:
    reg = LinearRegression()
    reg.fit(X, Y)

    coef = reg.coef_
    intercept = reg.intercept_
    output_ranges = {
        "score": (0.0, 1.0),
        "displayDuration": (1.0, 15.0),
        "compositeAlpha": (0.0, 1.0),
        "fontSize": (0.0, 1.0),
        "fontWeight": (0.0, 1.0),
    }
    outputs: dict[str, dict[str, Any]] = {}
    for row_index, output_name in enumerate(OUTPUT_NAMES):
        min_v, max_v = output_ranges[output_name]
        outputs[output_name] = {
            "intercept": float(intercept[row_index]),
            "coefficients": [float(v) for v in coef[row_index].tolist()],
            "min": float(min_v),
            "max": float(max_v),
        }

    metadata = {
        "trainer": "harness-swift/train/train_conductor_model.py",
        "samples": int(X.shape[0]),
        "features": int(X.shape[1]),
    }
    if metadata_extra:
        metadata.update(metadata_extra)

    payload = {
        "kind": "text-director-linear-v1",
        "version": "0.2.0",
        "featureOrder": INPUT_NAMES,
        "outputs": outputs,
        "metadata": metadata,
    }

    out_path = output_dir / f"{model_name}.backend.json"
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return out_path


# ---------------------------------------------------------------------------
# 7. Entrypoint
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Train ConductorTextDirector model")
    parser.add_argument("--samples", type=int, default=10_000, help="synthetic training samples")
    parser.add_argument("--corpus-samples", type=int, default=0, help="corpus-grounded training samples")
    parser.add_argument("--epochs", type=int, default=200, help="training epochs")
    parser.add_argument("--lr", type=float, default=1e-3, help="learning rate")
    parser.add_argument("--seed", type=int, default=42, help="random seed")
    parser.add_argument("--output-dir", type=str, default=None, help="output directory (default: ../Models)")

    parser.add_argument("--combined-bank", type=str, default=None, help="combined strict/loose JSON bank path")
    parser.add_argument("--strict-bank", type=str, default=None, help="strict bank path (txt/json)")
    parser.add_argument("--loose-bank", type=str, default=None, help="loose bank path (txt/json)")

    parser.add_argument("--semantic-teacher", choices=["off", "openai"], default="off")
    parser.add_argument("--semantic-augment-lines", type=int, default=0, help="LLM-generated corpus lines")
    parser.add_argument("--semantic-model", type=str, default="gpt-4.1-mini", help="OpenAI model for augmentation")
    parser.add_argument(
        "--semantic-api-key",
        type=str,
        default=os.environ.get("OPENAI_API_KEY"),
        help="OpenAI API key (defaults to OPENAI_API_KEY env)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    output_dir = Path(args.output_dir) if args.output_dir else repo_root / "Models"
    output_dir.mkdir(parents=True, exist_ok=True)

    combined_bank = Path(args.combined_bank).expanduser() if args.combined_bank else None
    strict_bank = Path(args.strict_bank).expanduser() if args.strict_bank else None
    loose_bank = Path(args.loose_bank).expanduser() if args.loose_bank else None

    print(f"[1/4] generating {args.samples} synthetic sample(s) ...")
    X_synth, Y_synth = generate_synthetic_data(args.samples, seed=args.seed)
    print(f"  synthetic X: {X_synth.shape}  Y: {Y_synth.shape}")

    corpus_candidates: list[CorpusCandidate] = []
    corpus_stats: dict[str, int] = {}
    if combined_bank or strict_bank or loose_bank:
        print("[2/4] loading corpus banks ...")
        try:
            corpus_candidates, corpus_stats = load_corpus_candidates(combined_bank, strict_bank, loose_bank)
            print(f"  loaded {len(corpus_candidates)} unique corpus lines: {corpus_stats}")
        except Exception as exc:
            print(f"  failed to load corpus banks: {exc}")
            sys.exit(1)
    else:
        print("[2/4] no corpus banks provided; skipping corpus loading.")

    if args.semantic_teacher == "openai" and args.semantic_augment_lines > 0:
        print(f"[2.5/4] semantic teacher augmentation requested ({args.semantic_augment_lines} lines) ...")
        augmented = openai_semantic_augment(
            corpus=corpus_candidates,
            count=args.semantic_augment_lines,
            model=args.semantic_model,
            api_key=args.semantic_api_key,
            seed=args.seed,
        )
        if augmented:
            corpus_candidates = dedupe_candidates([*corpus_candidates, *augmented])
            corpus_stats = {}
            for candidate in corpus_candidates:
                corpus_stats[candidate.bank] = corpus_stats.get(candidate.bank, 0) + 1
            print(f"  corpus after augmentation: {len(corpus_candidates)} line(s) {corpus_stats}")

    corpus_samples = args.corpus_samples
    if corpus_samples <= 0 and corpus_candidates:
        corpus_samples = max(4_000, args.samples // 2)

    if corpus_samples > 0 and corpus_candidates:
        X_corpus, Y_corpus = generate_corpus_aligned_data(
            corpus_candidates,
            n=corpus_samples,
            seed=args.seed,
        )
        print(f"  corpus X: {X_corpus.shape}  Y: {Y_corpus.shape}")
        X = np.concatenate([X_synth, X_corpus], axis=0)
        Y = np.concatenate([Y_synth, Y_corpus], axis=0)
    else:
        X = X_synth
        Y = Y_synth
        if corpus_samples > 0 and not corpus_candidates:
            print("  corpus_samples requested but no corpus lines available; training synthetic-only.")

    print(f"[3/4] training ConductorTextDirector for {args.epochs} epoch(s) ...")
    torch.manual_seed(args.seed)
    model = ConductorTextDirector()
    losses = train(model, X, Y, epochs=args.epochs, lr=args.lr)
    print(f"  final loss: {losses[-1]:.5f}")

    print("[4/4] exporting CoreML + backend model ...")
    coreml_path = convert_to_coreml(model, output_dir)
    backend_model_path = export_backend_linear_model(
        X,
        Y,
        output_dir,
        metadata_extra={
            "syntheticSamples": int(X_synth.shape[0]),
            "corpusSamples": int(X.shape[0] - X_synth.shape[0]),
            "corpusLineCount": int(len(corpus_candidates)),
            "corpusBanks": corpus_stats,
            "semanticTeacher": args.semantic_teacher,
            "semanticModel": args.semantic_model if args.semantic_teacher == "openai" else None,
            "semanticAugmentLinesRequested": int(args.semantic_augment_lines),
        },
    )
    print(f"  backend JSON model → {backend_model_path}")
    print(f"\ndone. model at: {coreml_path}")
    print(f"set CONDUCTOR_COREML_MODEL_PATH={coreml_path}")
    print(f"set CONDUCTOR_TEXT_DIRECTOR_MODEL_PATH={backend_model_path}")


if __name__ == "__main__":
    main()
