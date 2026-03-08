"""
Health Score Model
------------------
Computes a personalised daily health score (0-100) from wearable + mood data.

Initial params : height (cm), weight (kg), gender, age
Daily params   : steps, exercise_minutes, sleep_hours, resting_hr, mood (0-10)
Output         : score, per-metric breakdown, personalised weight recommendations

Scoring approach:
  Each metric is scored as a blend of:
    - Absolute score  (40%): where the value sits on a fixed clinical health scale
    - Personal score  (60%): deviation from the user's own rolling baseline
  This ensures objectively healthy values are always rewarded, while also
  recognising when a user is above or below their own norm.
  The final displayed score is a 3-day EMA to reduce day-to-day noise.
  Mood correlations shift metric weights over time to personalise.
"""

import numpy as np
from dataclasses import dataclass, field
from typing import Optional


# ─────────────────────────────────────────────────────────────────────────────
# National baselines — sourced from peer-reviewed population studies
# Stratified by age group + gender — used during cold start (<14 days of data)
#
# Steps:
#   Paluch et al. 2022, Lancet Public Health (meta-analysis, 15 cohorts)
#   — under-60 plateau: 8,000–10,000 steps/day
#   Paluch et al. 2021, JAMA Network Open (CARDIA study)
#   — median 9,146 steps/day; IQR 7,307–11,162 → SD ≈ 2,900
#
# Sleep:
#   CDC NHANES (2007–2018); MMWR 2016 (mm6506a1)
#   — mean ≈ 6.9–7.2 hrs; population SD ≈ 1.1 hrs
#
# Exercise minutes:
#   WHO guidelines: 150 min moderate/week ≈ 21 min/day
#   Realistic mean for wearable app users ≈ 25–40 min/day
#
# Resting HR:
#   AHA normal range 60–100 bpm; athlete norm 40–60 bpm
#   Population mean ~65–70 bpm, SD ~10 bpm
# ─────────────────────────────────────────────────────────────────────────────

NATIONAL_BASELINES = {
    #                        steps   ex_min  sleep_hrs  rhr
    ("<30",  "male"):    {"steps": 9500,  "exercise_min": 38, "sleep_hours": 7.0, "resting_hr": 65},
    ("<30",  "female"):  {"steps": 8500,  "exercise_min": 33, "sleep_hours": 7.2, "resting_hr": 67},
    ("30-50","male"):    {"steps": 7500,  "exercise_min": 32, "sleep_hours": 6.9, "resting_hr": 68},
    ("30-50","female"):  {"steps": 7000,  "exercise_min": 27, "sleep_hours": 7.0, "resting_hr": 70},
    ("50+",  "male"):    {"steps": 6500,  "exercise_min": 27, "sleep_hours": 7.0, "resting_hr": 70},
    ("50+",  "female"):  {"steps": 6000,  "exercise_min": 23, "sleep_hours": 7.1, "resting_hr": 72},
}

NATIONAL_STD = {
    "steps":        2900,
    "exercise_min":  22,
    "sleep_hours":   1.1,
    "resting_hr":   10.0,
}

# ─────────────────────────────────────────────────────────────────────────────
# Clinical zone scales — piecewise linear, maps raw metric value → 0–100 score
# Based on AHA, CDC, WHO, and wearable-study norms
# ─────────────────────────────────────────────────────────────────────────────

CLINICAL_ZONES = {
    # RHR: lower is better — athlete (<50) to concerning (>90)
    "resting_hr": {
        "x": [35,  45,  55,  65,  75,  85,  100],
        "y": [100, 93,  80,  60,  38,  18,   5],
    },
    # Sleep hours: optimal 7–9, penalties for too short or too long
    "sleep_hours": {
        "x": [0,   4,   5,   6,   7,   8,   9,   10,  12],
        "y": [0,   10,  32,  58,  82,  95,  90,  72,  50],
    },
    # Steps: based on Paluch 2022 dose-response curve
    "steps": {
        "x": [0,    2000, 4000, 6000, 7500, 10000, 12500, 15000],
        "y": [5,    18,   35,   55,   68,   82,    92,    98],
    },
    # Exercise minutes per day
    "exercise_min": {
        "x": [0,  5,   15,  21,  30,  45,  60,  90],
        "y": [5,  18,  38,  50,  68,  82,  92,  100],
    },
    # Sleep quality proxy (0–1): distance from 8-hour target
    "sleep_quality": {
        "x": [0.0, 0.4, 0.55, 0.65, 0.75, 0.85, 0.95, 1.0],
        "y": [5,   20,  38,   55,   70,   83,   93,   100],
    },
}

# ─────────────────────────────────────────────────────────────────────────────
# Base category weights — derived from RAIS dataset mixed-effects analysis
# blended 40% data-driven / 60% health-literature prior
# ─────────────────────────────────────────────────────────────────────────────

BASE_CATEGORY_WEIGHTS = {
    "recovery":      0.48,   # sleep duration, sleep quality
    "activity":      0.28,   # steps, exercise time
    "cardiovascular":0.15,   # resting HR
    "stability":     0.09,   # placeholder (SpO2, resp rate)
}

BASE_METRIC_WEIGHTS = {
    "sleep_hours":   ("recovery",      0.50),
    "sleep_quality": ("recovery",      0.50),
    "steps":         ("activity",      0.65),
    "exercise_min":  ("activity",      0.35),
    "resting_hr":    ("cardiovascular",1.00),
}

BASELINE_WINDOW        = 14    # days before switching from national → personal baseline
MIN_DAYS_FOR_WEIGHT_UPDATE = 1
MOOD_BLEND_MAX         = 0.45
ABSOLUTE_WEIGHT        = 0.40  # blend: 40% clinical zone, 60% personal baseline
SIGMOID_DAMPING        = 2.0   # widens sigmoid to reduce day-to-day variability
SCORE_EMA_WEIGHTS      = [0.50, 0.30, 0.20]  # most-recent to oldest (3-day EMA)


# ─────────────────────────────────────────────────────────────────────────────
# Data structures
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class DailyEntry:
    day: int
    steps: float
    exercise_min: float
    sleep_hours: float
    mood: float                        # 0–10
    resting_hr: Optional[float] = None
    sleep_quality: float = 0.0         # derived: distance from 8-hr target, 0–1


@dataclass
class ScoreResult:
    score: float                       # 0–100 (smoothed)
    score_raw: float                   # 0–100 (today only, unsmoothed)
    category_scores: dict              # per-category 0–100
    metric_scores: dict                # per-metric 0–100
    current_weights: dict
    recommendations: list
    days_of_data: int
    baseline_source: str


# ─────────────────────────────────────────────────────────────────────────────
# Model
# ─────────────────────────────────────────────────────────────────────────────

class HealthScoreModel:

    def __init__(self, height_cm: float, weight_kg: float, gender: str, age: int):
        self.height = height_cm
        self.weight = weight_kg
        self.gender = gender.lower()
        self.age    = age

        self.bmr       = self._compute_bmr()
        self.bmi       = weight_kg / (height_cm / 100) ** 2
        self.age_group = "<30" if age < 30 else ("30-50" if age <= 50 else "50+")
        self.national  = NATIONAL_BASELINES.get(
            (self.age_group, self.gender),
            NATIONAL_BASELINES[("30-50", "male")]
        )

        self.history:      list[DailyEntry] = []
        self.score_history: list[float]     = []

        self.metric_weights   = {k: v[1] for k, v in BASE_METRIC_WEIGHTS.items()}
        self.category_weights = dict(BASE_CATEGORY_WEIGHTS)

    # ── Setup ────────────────────────────────────────────────────────────────

    def _compute_bmr(self) -> float:
        base = 10 * self.weight + 6.25 * self.height - 5 * self.age
        return base + 5 if self.gender == "male" else base - 161

    # ── Logging ──────────────────────────────────────────────────────────────

    def log_day(
        self,
        steps: float,
        exercise_minutes: float,
        sleep_hours: float,
        mood: float,
        resting_hr: Optional[float] = None,
    ) -> ScoreResult:
        """
        Record a day's metrics and return today's score + recommendations.
        Call once per day in chronological order.
        """
        sleep_quality = max(0.0, 1.0 - abs(sleep_hours - 8.0) / 4.0)

        entry = DailyEntry(
            day          = len(self.history) + 1,
            steps        = steps,
            exercise_min = exercise_minutes,
            sleep_hours  = sleep_hours,
            mood         = mood,
            resting_hr   = resting_hr,
            sleep_quality= sleep_quality,
        )
        self.history.append(entry)

        self._update_weights()

        return self._compute_score(entry)

    # ── Scoring ──────────────────────────────────────────────────────────────

    def _get_baseline(self) -> tuple[dict, dict, str]:
        if len(self.history) < BASELINE_WINDOW:
            means = {
                "steps":        self.national["steps"],
                "exercise_min": self.national["exercise_min"],
                "sleep_hours":  self.national["sleep_hours"],
                "sleep_quality":0.75,
                "resting_hr":   self.national["resting_hr"],
            }
            stds = {k: NATIONAL_STD.get(k, means[k] * 0.2) for k in means}
            return means, stds, "national"

        window = self.history[-BASELINE_WINDOW:]
        keys   = ["steps", "exercise_min", "sleep_hours", "sleep_quality"]
        means  = {k: float(np.median([getattr(e, k) for e in window])) for k in keys}
        stds   = {k: float(np.std([getattr(e, k) for e in window]) + 1e-6) for k in keys}

        # RHR personal baseline (only from days where it was recorded)
        rhr_vals = [e.resting_hr for e in window if e.resting_hr is not None]
        if rhr_vals:
            means["resting_hr"] = float(np.median(rhr_vals))
            stds["resting_hr"]  = float(np.std(rhr_vals) + 1e-6)
        else:
            means["resting_hr"] = self.national["resting_hr"]
            stds["resting_hr"]  = NATIONAL_STD["resting_hr"]

        return means, stds, "personal"

    def _absolute_score(self, metric: str, value: float) -> float:
        """Score based on fixed clinical health zones (0–100)."""
        zone = CLINICAL_ZONES.get(metric)
        if zone is None:
            return 50.0
        return float(np.interp(value, zone["x"], zone["y"]))

    def _get_mood_optimal(self, metric: str) -> Optional[float]:
        """
        Return the mood-weighted centroid of historical values for this metric.
        Uses softmax weighting by mood so high-mood days pull the target more strongly.
        Returns None if fewer than 3 data points are available.
        """
        if metric == "resting_hr":
            pairs = [(e.resting_hr, e.mood) for e in self.history if e.resting_hr is not None]
        else:
            pairs = [(getattr(e, metric), e.mood) for e in self.history]

        if len(pairs) < 3:
            return None

        values = np.array([v for v, _ in pairs], dtype=float)
        moods  = np.array([m for _, m in pairs], dtype=float)

        # Softmax over mood scores so higher-mood days dominate the target
        mood_weights = np.exp(moods - moods.max()) + 1e-6
        return float(np.average(values, weights=mood_weights))

    def _personal_score(self, value: float, target: float, std: float, direction: int = 1) -> float:
        """
        Score based on proximity to the mood-optimal target (0–100).
        Sigmoid centred at target; SIGMOID_DAMPING widens the curve.
        """
        z = direction * (value - target) / (std * SIGMOID_DAMPING)
        return float(100 / (1 + np.exp(-z)))

    def _blend_score(self, metric: str, value: float, mean: float, std: float, direction: int = 1) -> float:
        """
        Blend absolute clinical score (40%) + mood-optimal personal score (60%).
        Personal target starts at the population/personal baseline mean and shifts
        toward the user's mood-optimal value as mood data accumulates.
        """
        abs_s = self._absolute_score(metric, value)

        alpha     = MOOD_BLEND_MAX * (1 - np.exp(-len(self.history) / 30.0))
        mood_opt  = self._get_mood_optimal(metric)
        target    = (1 - alpha) * mean + alpha * mood_opt if mood_opt is not None else mean

        per_s = self._personal_score(value, target, std, direction)
        return ABSOLUTE_WEIGHT * abs_s + (1 - ABSOLUTE_WEIGHT) * per_s

    def _compute_score(self, entry: DailyEntry) -> ScoreResult:
        means, stds, source = self._get_baseline()

        raw = {
            "sleep_hours":   self._blend_score("sleep_hours",   entry.sleep_hours,   means["sleep_hours"],   stds["sleep_hours"],   +1),
            "sleep_quality": self._blend_score("sleep_quality", entry.sleep_quality, means["sleep_quality"], stds["sleep_quality"], +1),
            "steps":         self._blend_score("steps",         entry.steps,         means["steps"],         stds["steps"],         +1),
            "exercise_min":  self._blend_score("exercise_min",  entry.exercise_min,  means["exercise_min"],  stds["exercise_min"],  +1),
        }

        # RHR: only include if provided today
        if entry.resting_hr is not None:
            raw["resting_hr"] = self._blend_score("resting_hr", entry.resting_hr, means["resting_hr"], stds["resting_hr"], -1)

        # Category scores
        category_totals     = {c: 0.0 for c in BASE_CATEGORY_WEIGHTS}
        category_weight_sum = {c: 0.0 for c in BASE_CATEGORY_WEIGHTS}

        for metric, score in raw.items():
            cat = BASE_METRIC_WEIGHTS[metric][0]
            w   = self.metric_weights[metric]
            category_totals[cat]     += score * w
            category_weight_sum[cat] += w

        category_scores = {
            c: (category_totals[c] / category_weight_sum[c]) if category_weight_sum[c] > 0 else 50.0
            for c in BASE_CATEGORY_WEIGHTS
        }

        # Exclude categories that had no contributing metrics (e.g. stability placeholder)
        active_cats   = {c: s for c, s in category_scores.items() if category_weight_sum[c] > 0}
        active_weight = sum(self.category_weights[c] for c in active_cats)
        raw_score = sum(
            (self.category_weights[c] / active_weight) * s for c, s in active_cats.items()
        )

        # 3-day EMA smoothing
        self.score_history.append(raw_score)
        n = len(self.score_history)
        if n >= 3:
            w = SCORE_EMA_WEIGHTS
            smoothed = w[0]*self.score_history[-1] + w[1]*self.score_history[-2] + w[2]*self.score_history[-3]
        elif n == 2:
            smoothed = 0.65 * self.score_history[-1] + 0.35 * self.score_history[-2]
        else:
            smoothed = raw_score

        return ScoreResult(
            score          = round(smoothed, 1),
            score_raw      = round(raw_score, 1),
            category_scores= {k: round(v, 1) for k, v in category_scores.items()},
            metric_scores  = {k: round(v, 1) for k, v in raw.items()},
            current_weights= self._readable_weights(),
            recommendations= self._build_recommendations(entry, raw, means),
            days_of_data   = len(self.history),
            baseline_source= source,
        )

    # ── Weight personalisation ────────────────────────────────────────────────

    def _update_weights(self):
        """
        Correlate each metric's deviation from baseline with mood.
        Metrics that co-vary with the user's own mood get higher weight.
        """
        means, stds, _ = self._get_baseline()
        metrics = ["sleep_hours", "sleep_quality", "steps", "exercise_min", "resting_hr"]
        moods   = np.array([e.mood for e in self.history])

        correlations = {}
        for m in metrics:
            if m == "resting_hr":
                values = np.array([e.resting_hr for e in self.history if e.resting_hr is not None])
                m_moods = np.array([e.mood for e in self.history if e.resting_hr is not None])
            else:
                values  = np.array([getattr(e, m) for e in self.history])
                m_moods = moods

            if len(values) < 2 or np.std(values) < 1e-6 or np.std(m_moods) < 1e-6:
                correlations[m] = 0.0
                continue

            mean_v = means.get(m, float(np.mean(values)))
            std_v  = stds.get(m, 1.0)
            deviations = (values - mean_v) / (std_v + 1e-6)
            # RHR: invert deviations so lower = positive signal
            if m == "resting_hr":
                deviations = -deviations

            r = float(np.corrcoef(deviations, m_moods)[0, 1])
            correlations[m] = max(0.0, r)

        # Exponential growth: small on day 1 (~2%), meaningful by day 14 (~17%), near-max by day 90 (~43%)
        alpha = MOOD_BLEND_MAX * (1 - np.exp(-len(self.history) / 30.0))

        base_weights = {k: BASE_METRIC_WEIGHTS[k][1] for k in metrics}
        corr_total   = sum(correlations.values()) + 1e-6
        corr_norm    = {k: v / corr_total for k, v in correlations.items()}

        for m in metrics:
            self.metric_weights[m] = (1 - alpha) * base_weights[m] + alpha * corr_norm[m]

        # Renormalise within each category
        for cat in BASE_CATEGORY_WEIGHTS:
            cat_metrics = [m for m in metrics if BASE_METRIC_WEIGHTS[m][0] == cat]
            total = sum(self.metric_weights[m] for m in cat_metrics)
            if total > 0:
                for m in cat_metrics:
                    self.metric_weights[m] /= total

    # ── Recommendations ───────────────────────────────────────────────────────

    def _build_recommendations(self, entry: DailyEntry, scores: dict, means: dict) -> list:
        recs = []

        if scores.get("sleep_hours", 100) < 45:
            deficit = round(means["sleep_hours"] - entry.sleep_hours, 1)
            recs.append(f"Sleep is {deficit}h below your baseline — prioritise rest tonight.")

        if scores.get("steps", 100) < 45:
            deficit = int(means["steps"] - entry.steps)
            recs.append(f"Steps are {deficit:,} below your baseline. A short walk would help.")

        if scores.get("exercise_min", 100) < 45:
            recs.append("Exercise time is low today. Even 15 minutes of moderate activity counts.")

        if entry.resting_hr is not None and scores.get("resting_hr", 100) < 45:
            recs.append(f"Resting HR ({entry.resting_hr:.0f} bpm) is elevated — consider rest or stress management.")

        if entry.mood <= 3:
            recs.append("Mood is low — your score is weighted toward metrics you personally find meaningful.")

        if not recs:
            recs.append("All metrics are on track. Keep it up.")

        if len(self.history) >= MIN_DAYS_FOR_WEIGHT_UPDATE:
            top = max(self.metric_weights, key=self.metric_weights.get)
            label = {
                "sleep_hours":   "sleep duration",
                "sleep_quality": "sleep consistency",
                "steps":         "daily steps",
                "exercise_min":  "exercise time",
                "resting_hr":    "resting heart rate",
            }.get(top, top)
            recs.append(f"Based on your mood patterns, {label} is currently your most impactful metric.")

        return recs

    def _readable_weights(self) -> dict:
        return {
            "category_weights": {k: round(v, 3) for k, v in self.category_weights.items()},
            "metric_weights":   {k: round(v, 3) for k, v in self.metric_weights.items()},
        }


# ─────────────────────────────────────────────────────────────────────────────
# Demo — real RHR data, constant other metrics
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import openpyxl

    # Male, 5'8" = 172.7cm, 150lbs = 68kg, age 18
    model = HealthScoreModel(height_cm=172.7, weight_kg=68.0, gender="male", age=18)

    wb = openpyxl.load_workbook('/Users/nicholaske/Downloads/SampleRHR.xlsx')
    rhr_data = [(row[0][:10], row[3]) for row in wb.active.iter_rows(values_only=True)]

    CONST_STEPS    = 8500
    CONST_EXERCISE = 35
    CONST_SLEEP    = 7.5
    CONST_MOOD     = 7.0

    print(f"User: Male, 5'8\", 150 lbs, age 18  |  BMR: {model.bmr:.0f} kcal")
    print(f"Constants: steps={CONST_STEPS}, exercise={CONST_EXERCISE}min, sleep={CONST_SLEEP}h, mood={CONST_MOOD}\n")
    print(f"{'Day':<4} {'Date':<12} {'RHR':>4} {'RHR Abs':>8} {'Score(raw)':>10} {'Score(smooth)':>13} {'Src':<9}")
    print("-" * 70)

    for i, (date, rhr) in enumerate(rhr_data):
        result = model.log_day(
            steps           = CONST_STEPS,
            exercise_minutes= CONST_EXERCISE,
            sleep_hours     = CONST_SLEEP,
            mood            = CONST_MOOD,
            resting_hr      = rhr,
        )
        rhr_abs = result.metric_scores.get("resting_hr", "-")
        print(
            f"{i+1:<4} {date:<12} {rhr:>4}  "
            f"{rhr_abs:>7.1f}  "
            f"{result.score_raw:>9.1f}  "
            f"{result.score:>12.1f}  "
            f"{result.baseline_source}"
        )

    print("\n── Summary ─────────────────────────────────────────────")
    rhrs   = [r[1] for r in rhr_data]
    scores = model.score_history
    print(f"  RHR range    : {min(rhrs)}–{max(rhrs)} bpm  (mean {np.mean(rhrs):.1f})")
    print(f"  Score range  : {min(scores):.1f}–{max(scores):.1f}  (mean {np.mean(scores):.1f})")
    print(f"  Score swing  : {max(scores)-min(scores):.1f} pts  (was 16.0 pts before fix)")
