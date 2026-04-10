#!/usr/bin/env python3
"""
Conductor text-director model: training pipeline.

Generates synthetic training data from heuristic presentation rules, trains a
multi-output MLP, converts to CoreML (.mlpackage), and compiles to .mlmodelc.

Inputs (14 features):
    weight            – candidate baseline weight           [0, 1]
    arc               – narrative arc (1, 2, 3)
    textLength        – normalised character count          [0, 1]
    textAmount        – user param vector                   [0, 1]
    compositeBias     – user param vector                   [0, 1]
    audioGain         – user param vector                   [0, 1]
    spatialX          – user param vector                   [0, 1]
    spatialY          – user param vector                   [0, 1]
    spatialZ          – user param vector                   [0, 1]
    isMain            – 1 if current state == main          {0, 1}
    audioRMS          – audio loudness (placeholder)        [0, 1]
    audioSpectralCentroid – audio brightness (placeholder)  [0, 1]
    videoLuminance    – frame brightness (placeholder)      [0, 1]
    videoMotion       – inter-frame motion (placeholder)    [0, 1]

Outputs (5 values):
    score             – selection score                     [0, 1]
    displayDuration   – seconds to show text                [1, 15]
    compositeAlpha    – text overlay opacity                [0, 1]
    fontSize          – normalised font size                [0, 1]
    fontWeight        – normalised font weight              [0, 1]

Usage:
    pip install -r requirements.txt
    python train_conductor_model.py           # generates Models/ConductorTextDirector.mlmodelc
    python train_conductor_model.py --samples 50000 --epochs 400   # heavier training
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

# ---------------------------------------------------------------------------
# 1. Synthetic data generation
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


def generate_synthetic_data(n: int, seed: int = 42) -> tuple[np.ndarray, np.ndarray]:
    """Return (X, Y) arrays shaped (n, 14) and (n, 5)."""
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

    # --- heuristic scoring (mirrors HeuristicScoringModel in Swift) ---
    score = weight + text_amount * 0.25 + composite_bias * 0.15 + is_main * 0.20
    # bonus from audio energy and video activity
    score += audio_rms * 0.10 + video_motion * 0.05
    score = np.clip(score, 0.0, 2.0) / 2.0  # normalise to [0, 1]

    # --- display duration: longer text + more textAmount → longer display ---
    display_duration = 3.0 + text_length * 7.0 + text_amount * 3.0
    display_duration -= audio_rms * 2.0  # loud moments → quicker cuts
    display_duration += (1.0 - video_motion) * 1.5  # still scenes → linger
    display_duration = np.clip(display_duration, 1.0, 15.0)

    # --- composite alpha: compositeBias drives base, audioGain boosts ---
    composite_alpha = composite_bias * 0.55 + 0.35 + audio_gain * 0.10
    composite_alpha = np.clip(composite_alpha, 0.2, 1.0)

    # --- font size: textAmount primary driver, audio adds emphasis ---
    font_size = text_amount * 0.45 + 0.25 + audio_rms * 0.15 + video_lum * 0.10
    font_size = np.clip(font_size, 0.15, 1.0)

    # --- font weight: compositeBias + spatial energy ---
    spatial_energy = np.sqrt(spatial_x**2 + spatial_y**2 + spatial_z**2) / np.sqrt(3.0)
    font_weight = composite_bias * 0.40 + 0.25 + spatial_energy * 0.20 + audio_rms * 0.15
    font_weight = np.clip(font_weight, 0.1, 1.0)

    # Add a little noise so the model doesn't memorise exact rules
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
            weight, arc, text_length, text_amount, composite_bias,
            audio_gain, spatial_x, spatial_y, spatial_z, is_main,
            audio_rms, audio_spectral, video_lum, video_motion,
        ]
    )
    Y = np.column_stack([score, display_duration, composite_alpha, font_size, font_weight])
    return X.astype(np.float32), Y.astype(np.float32)


# ---------------------------------------------------------------------------
# 2. Model definition
# ---------------------------------------------------------------------------

class ConductorTextDirector(nn.Module):
    """Small MLP: 14 → 64 → 32 → 5 with residual shortcut on the hidden layers."""

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
        h = self.act(self.bn2(self.fc2(h))) + h  # residual
        h = self.act(self.bn3(self.fc3(h)))
        return self.head(h)


# ---------------------------------------------------------------------------
# 3. Training loop
# ---------------------------------------------------------------------------

def train(
    model: ConductorTextDirector,
    X: np.ndarray,
    Y: np.ndarray,
    epochs: int = 200,
    lr: float = 1e-3,
    batch_size: int = 256,
) -> list[float]:
    """Train the model, return per-epoch losses."""
    Xt = torch.from_numpy(X)
    Yt = torch.from_numpy(Y)
    dataset = TensorDataset(Xt, Yt)
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    # Loss weights: score matters most, duration is in different scale
    output_weights = torch.tensor([2.0, 0.1, 1.0, 1.0, 1.0])  # per-output importance

    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    criterion = nn.MSELoss(reduction="none")

    losses = []
    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        for xb, yb in loader:
            pred = model(xb)
            per_output = criterion(pred, yb).mean(dim=0)  # (5,)
            loss = (per_output * output_weights).sum()
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            epoch_loss += loss.item()
        scheduler.step()
        avg = epoch_loss / len(loader)
        losses.append(avg)
        if (epoch + 1) % 50 == 0 or epoch == 0:
            print(f"  epoch {epoch+1:4d}/{epochs}  loss={avg:.5f}")
    return losses


# ---------------------------------------------------------------------------
# 4. CoreML conversion + compilation
# ---------------------------------------------------------------------------

class _ExportWrapper(nn.Module):
    """Wrapper that takes 14 individual scalar tensors so CoreML gets named inputs."""

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
                weight, arc, textLength, textAmount, compositeBias,
                audioGain, spatialX, spatialY, spatialZ, isMain,
                audioRMS, audioSpectralCentroid, videoLuminance, videoMotion,
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
    """Trace, convert to CoreML .mlpackage, compile to .mlmodelc."""
    import coremltools as ct

    model.eval()
    wrapper = _ExportWrapper(model)
    wrapper.eval()

    example_inputs = tuple(torch.tensor([0.5]) for _ in INPUT_NAMES)
    traced = torch.jit.trace(wrapper, example_inputs)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name=name, shape=(1,), dtype=np.float32)
            for name in INPUT_NAMES
        ],
        outputs=[ct.TensorType(name=name) for name in OUTPUT_NAMES],
        minimum_deployment_target=ct.target.macOS14,
    )

    mlmodel.author = "ConductorHarness training pipeline"
    mlmodel.short_description = (
        "Text-director model: selects text from a script bank and directs "
        "presentation (duration, compositing, font size, weight) based on "
        "audio/video/user-parameter inputs."
    )
    mlmodel.version = "0.1.0"

    package_path = output_dir / f"{model_name}.mlpackage"
    mlmodel.save(str(package_path))
    print(f"  saved .mlpackage → {package_path}")

    # Compile to .mlmodelc using xcrun
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
        print("  falling back: .mlpackage saved; compile manually with Xcode.")
        return package_path

    print(f"  compiled .mlmodelc → {compiled_path}")
    return compiled_path


# ---------------------------------------------------------------------------
# 5. Entrypoint
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Train ConductorTextDirector CoreML model")
    parser.add_argument("--samples", type=int, default=10_000, help="synthetic training samples")
    parser.add_argument("--epochs", type=int, default=200, help="training epochs")
    parser.add_argument("--lr", type=float, default=1e-3, help="learning rate")
    parser.add_argument("--seed", type=int, default=42, help="random seed")
    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="output directory (default: ../Models)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    output_dir = Path(args.output_dir) if args.output_dir else repo_root / "Models"
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"[1/3] generating {args.samples} synthetic training samples ...")
    X, Y = generate_synthetic_data(args.samples, seed=args.seed)
    print(f"  X shape: {X.shape}  Y shape: {Y.shape}")

    print(f"[2/3] training ConductorTextDirector for {args.epochs} epochs ...")
    torch.manual_seed(args.seed)
    model = ConductorTextDirector()
    losses = train(model, X, Y, epochs=args.epochs, lr=args.lr)
    print(f"  final loss: {losses[-1]:.5f}")

    print("[3/3] converting to CoreML + compiling ...")
    out_path = convert_to_coreml(model, output_dir)
    print(f"\ndone. model at: {out_path}")
    print(f"set CONDUCTOR_COREML_MODEL_PATH={out_path} or place in ./Models/ to load at runtime.")


if __name__ == "__main__":
    main()
