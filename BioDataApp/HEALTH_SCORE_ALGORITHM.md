# Health Score Algorithm — Complete Summary

This document describes how the **TallyWell / VitaMetric** health score model computes a personalised daily health score (0–100) from wearable and mood data.

---

## 1. Overview

- **Purpose:** Turn raw daily metrics (steps, exercise, sleep, resting HR, mood) into a single 0–100 score and per-metric breakdown, with recommendations and goals that adapt to the user.
- **Inputs:**
  - **Profile (one-time):** height (cm), weight (kg), gender, age.
  - **Daily:** steps, exercise minutes, sleep hours, mood (0–10), resting HR (optional).
- **Outputs:** Smoothed score (0–100), raw score, category scores, metric scores, recommendations, baseline source, and (for the app) goals for the radar chart.

Scoring combines:

1. **Absolute (clinical) score** — where the value sits on fixed health benchmarks.
2. **Personal score** — how close the value is to the user’s own baseline (or mood-optimal target).
3. A **dynamic blend** of the two: when the clinical score is high, it dominates; when it’s low, personal progress matters more.
4. **3-day EMA** on the raw score to get the final displayed score and reduce noise.
5. **Mood-driven personalisation** — metric weights and personal targets shift over time using mood–metric relationships.

---

## 2. Baselines (Targets)

The model needs a **baseline** (mean and spread) for each metric to score “personal” performance and to define goals.

### 2.1 National baseline (cold start)

- Used when the user has **fewer than 14 days** of history (`BASELINE_WINDOW = 14`).
- Comes from **`NATIONAL_BASELINES`**, stratified by **age group** and **gender**:
  - Age groups: `<30`, `30-50`, `50+`.
  - Values are from population/guideline studies (e.g. Paluch for steps, CDC for sleep, WHO for exercise, AHA for resting HR).

Example (male, &lt;30):

- steps: 9,500  
- exercise_min: 38  
- sleep_hours: 7.0  
- resting_hr: 65  

Standard deviations use **`NATIONAL_STD`** (e.g. steps 2,900, sleep 1.1 h, resting_hr 10 bpm).

### 2.2 Personal baseline (warm)

- Used when there are **≥ 14 days** of history.
- **Means:** median of each metric over the last 14 days.
- **Stds:** standard deviation over the same window (+ small constant to avoid division by zero).
- **Resting HR:** personal mean/std only over days where resting HR was recorded; otherwise falls back to national.

So targets and “how far from normal” are **national** at first, then **personal** once enough data exists.

---

## 3. Per-metric scoring (0–100)

Each metric is turned into a 0–100 score by blending **absolute** and **personal** scores.

### 3.1 Absolute score (clinical zones)

- **`CLINICAL_ZONES`** define piecewise-linear curves: raw value → 0–100.
- **Resting HR:** lower is better (e.g. 35→100, 65→60, 100→5).
- **Sleep hours:** optimal band (e.g. 7–9 h); penalties for too short or too long.
- **Steps:** increasing curve (e.g. Paluch-style), saturating at high steps.
- **Exercise min:** increasing with guidelines (e.g. 21 min/day reference).
- **Sleep quality:** derived as `1 - |sleep_hours - 8| / 4`, clamped to [0,1], then mapped via a zone.

So each metric has a fixed “health benchmark” score independent of the user’s history.

### 3.2 Personal score (vs target)

- **Target** for a metric = baseline mean, then gradually blended with a **mood-optimal** value (see below).
- **Personal score** = sigmoid around that target:
  - `z = direction * (value - target) / (std * SIGMOID_DAMPING)`
  - `personal_score = 100 / (1 + exp(-z))`
- **Direction:** +1 for “higher is better” (steps, sleep, exercise), −1 for resting HR.

So the personal score measures “how close to your (mood-informed) target” you are.

### 3.3 Mood-optimal target

- For each metric, the model can compute a **mood-weighted average** of past values:
  - Weights = softmax(mood) so **high-mood days** pull the target more.
- Requires **≥ 3** history points; otherwise no mood-optimal, only baseline mean.
- **Target** = `(1 - α) * baseline_mean + α * mood_optimal`, where α increases with history length (capped by `MOOD_BLEND_MAX`, e.g. 0.45).

So over time, “your target” shifts toward the values you had on good-mood days.

### 3.4 Dynamic blend (absolute vs personal)

- **Absolute score** and **personal score** are combined with a **single weight** that depends on the absolute score itself:
  - `w_abs = clip(absolute_score / 100, ABSOLUTE_WEIGHT_MIN, ABSOLUTE_WEIGHT_MAX)` (e.g. 0.05–0.95).
  - **Blended score** = `w_abs * absolute_score + (1 - w_abs) * personal_score`.
- So:
  - **High clinical score** → blend is mostly absolute (benchmark dominates).
  - **Low clinical score** → blend is more personal (progress and your own target matter more).

This is applied per metric; resting HR uses the same formula with `direction = -1`.

---

## 4. Categories and weights

- Metrics are grouped into **categories** (e.g. recovery, activity, cardiovascular) with **base category weights** (e.g. recovery 0.48, activity 0.28, cardiovascular 0.15).
- Each metric has a **base metric weight** within its category (e.g. steps 0.65, exercise 0.35 in activity).
- **Metric weights** start from these bases and are **updated over time** from data (see Section 7).
- **Category score** = weighted average of that category’s metric scores (using current metric weights).
- Category scores are used for breakdown, recommendations, and (when mood regression isn’t used) for the raw score.

---

## 5. Raw score (single 0–100 number)

The model produces a **raw score** for the day in one of two ways:

### 5.1 Mood regression (preferred when enough data)

- With **≥ 5 days** of history, it fits: **mood = β · x + intercept**, where **x** is the 5 standardized metrics (steps, exercise_min, sleep_hours, sleep_quality, resting_hr), z-scored using the current baseline.
- Regression is **Bayesian linear regression** (Gaussian prior on β and intercept, normal likelihood).
- **Predicted mood** for today’s metrics is computed, clipped to [0, 10].
- **Raw score** = `predicted_mood * 10` (so 0–100).

So when possible, the “score” is literally “predicted mood from your metrics,” scaled to 0–100.

### 5.2 Category-weighted fallback

- If regression isn’t available (e.g. &lt; 5 days), **raw score** = weighted average of **category scores**, using only categories that have at least one metric with weight &gt; 0.

---

## 6. Smoothing (3-day EMA)

- The **displayed score** is a **3-day exponential moving average** of the raw score:
  - Weights (most recent → oldest): e.g. `[0.50, 0.30, 0.20]` (`SCORE_EMA_WEIGHTS`).
- When **replacing** a past day, the stored raw score for that day is updated; the smoothed value for that day is recomputed from the (updated) 3-day window.
- So the number the user sees is **smoothed**; the “raw” score is still the direct output of the scoring step above.

---

## 7. Weight personalisation (metric weights)

Metric weights (within categories) are updated so that **metrics that better predict mood** get more influence over time.

### 7.1 Bayesian regression path (preferred)

- With **≥ 5 days**, the same **mood ~ metrics** Bayesian regression is used.
- **Learned weights** = `|β|` (absolute value of regression coefficients), normalized within each category.
- **Updated metric weight** = `(1 - α) * base_weight + α * learned_weight`, with α increasing in history length (same α logic as for mood-optimal target).
- So weights drift from literature/base weights toward “what predicts your mood.”

### 7.2 Correlation fallback

- If regression isn’t used (e.g. too little data or numerical issue), a **correlation-based** update is used:
  - For each metric, compute correlation between (standardized metric) and mood (resting HR: lower is better, so sign is flipped).
  - Correlations are truncated at 0 and normalized to sum to 1.
  - New weights = blend of base weights and these correlation-based weights (again with α).

---

## 8. Recommendations

- **Recommendations** are generated from:
  - **Low metric scores** (e.g. &lt; 45): sleep deficit, steps below baseline, low exercise, elevated resting HR.
  - **Very low mood** (e.g. ≤ 3): message that the score is weighted toward metrics that matter for the user.
  - **Default:** “All metrics on track.”
  - If weights have been updated (≥ 1 day of weight updates), add a line that the **top-weighted metric** is currently the most impactful for their mood.

---

## 9. Goals (for radar chart)

- **`get_goals()`** returns the current **target** for each metric used in the app’s radar chart:
  - steps, exercise_min, sleep_hours, resting_hr from the **current baseline** (national or personal).
  - **Mood** goal is fixed at **7.5** (on 0–10).
- So the radar’s “outer ring” is exactly the model’s current targets and shifts as the user moves from national to personal baseline and as history (and optionally mood-optimal) evolves.

---

## 10. Data flow (one day)

1. **Ingest day:** steps, exercise_min, sleep_hours, mood, optional resting_hr; derive sleep_quality from sleep_hours.
2. **Baseline:** Compute mean/std (national or last-14-days personal).
3. **Per-metric score:** For each metric, compute absolute score (clinical zones) and personal score (vs target); blend with dynamic weight.
4. **Category scores:** Aggregate metric scores by category using current metric weights.
5. **Raw score:** If enough history, predict mood from metrics and set raw = predicted_mood × 10; else use category-weighted average.
6. **Smoothing:** Update 3-day EMA and set displayed score.
7. **Weights:** Update metric weights (Bayesian or correlation).
8. **Output:** Score (smoothed), score_raw, category_scores, metric_scores, recommendations, baseline_source, and (via separate call) goals.

---

## 11. Key constants (summary)

| Constant | Typical value | Role |
|----------|----------------|------|
| `BASELINE_WINDOW` | 14 | Days before switching to personal baseline. |
| `MOOD_BLEND_MAX` | 0.45 | Max blend toward mood-optimal target / learned weights. |
| `ABSOLUTE_WEIGHT_MIN/MAX` | 0.05, 0.95 | Bounds on absolute vs personal blend weight. |
| `SIGMOID_DAMPING` | 2.0 | Widens sigmoid for personal score (less jumpy). |
| `SCORE_EMA_WEIGHTS` | [0.50, 0.30, 0.20] | 3-day EMA weights (recent → older). |
| `MIN_DAYS_FOR_REGRESSION` | 5 | Min history for mood regression and Bayesian weight update. |
| `BAYES_PRIOR_PRECISION` | 0.5 | Prior precision (regularisation) for regression. |
| `BAYES_LIKELIHOOD_VAR` | 2.0 | Likelihood variance for mood (0–10 scale). |

---

## 12. References (from code comments)

- **Steps:** Paluch et al. (e.g. Lancet Public Health 2022, JAMA Network Open 2021).
- **Sleep:** CDC NHANES, MMWR.
- **Exercise:** WHO guidelines (~21 min/day moderate).
- **Resting HR:** AHA normal ranges.
- **Category weights:** RAIS dataset mixed-effects analysis (40% data / 60% prior).

---

*This summary reflects the implementation in `health_score_model.py`.*
