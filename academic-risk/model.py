"""One portable PyTorch classifier, including preprocessing and calibration buffers."""
from __future__ import annotations

import os
os.environ.setdefault('CUBLAS_WORKSPACE_CONFIG', ':4096:8')
from pathlib import Path
import random
import numpy as np
import torch
from torch import nn

FEATURES = [
    'current_grade', 'latest_grade', 'grade_trend', 'grade_std', 'progress',
    'assessment_count', 'graded_fraction', 'overdue_fraction', 'late_fraction',
    'passing_grade', 'previous_failures', 'study_time', 'activities', 'university',
]


def seed_everything(seed: int):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    torch.set_num_threads(2)
    torch.use_deterministic_algorithms(True)
    torch.backends.cudnn.benchmark = False


class CourseRiskModel(nn.Module):
    def __init__(self, hidden=(32, 16), dropout=0.15):
        super().__init__()
        n = len(FEATURES)
        self.register_buffer('median', torch.zeros(n))
        self.register_buffer('mean', torch.zeros(n))
        self.register_buffer('scale', torch.ones(n))
        # Sigmoid calibration depends on raw logit and education level, in one model.
        self.register_buffer('calibration', torch.tensor([1., 0., 0.]))
        self.register_buffer('threshold', torch.tensor(0.5))
        self.margin_strength = nn.Parameter(torch.tensor(2.))
        layers = []
        dim = n * 2
        for width in hidden:
            layers += [nn.Linear(dim, width), nn.SiLU(), nn.Dropout(dropout)]
            dim = width
        layers.append(nn.Linear(dim, 1))
        self.network = nn.Sequential(*layers)

    def fit_preprocessing(self, x: np.ndarray):
        # Fit exclusively on training features; all-missing optional columns get zero.
        med = np.array([np.nanmedian(x[:, c]) if np.isfinite(x[:, c]).any() else 0. for c in range(x.shape[1])])
        filled = np.where(np.isnan(x), med, x)
        mean, scale = filled.mean(axis=0), filled.std(axis=0)
        scale = np.where(scale < 1e-6, 1., scale)
        self.median.copy_(torch.tensor(med, dtype=torch.float32))
        self.mean.copy_(torch.tensor(mean, dtype=torch.float32))
        self.scale.copy_(torch.tensor(scale, dtype=torch.float32))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        missing = torch.isnan(x)
        filled = torch.where(missing, self.median, x)
        standardized = (filled - self.mean) / self.scale
        residual = self.network(torch.cat([standardized, missing.float()], dim=1)).squeeze(-1)
        margin = filled[:, FEATURES.index('current_grade')] - filled[:, FEATURES.index('passing_grade')]
        return residual - torch.nn.functional.softplus(self.margin_strength) * margin

    def probability(self, x: torch.Tensor) -> torch.Tensor:
        raw = self(x)
        return torch.sigmoid(self.calibration[0] * raw + self.calibration[1] * x[:, -1] + self.calibration[2])


def load_model(path: Path):
    checkpoint = torch.load(path, map_location='cpu', weights_only=True)
    if checkpoint['features'] != FEATURES:
        raise ValueError('Model feature schema differs from the installed prediction code')
    model = CourseRiskModel(**checkpoint['architecture'])
    model.load_state_dict(checkpoint['state_dict'])
    model.eval()
    return model, checkpoint['metadata']


def predict_arrays(model, array, device='cpu', calibrated=True):
    model.eval()
    results = []
    with torch.no_grad():
        for start in range(0, len(array), 4096):
            x = torch.tensor(array[start:start+4096], dtype=torch.float32, device=device)
            value = model.probability(x) if calibrated else torch.sigmoid(model(x))
            results.append(value.cpu().numpy())
    return np.concatenate(results).astype(float)
