# Health App — Project Notes

## What it is
- **Health Score Model**: Computes a personalised daily health score (0–100) from wearable + mood data.
- **Health Score Tester**: Web UI to try the model (profile, log days, view score + recommendations).

## How to run
```bash
# From project folder
python health_score_tester.py
```
Then open http://localhost:8080 (or the Network URL printed). Set profile → log days → see score and recommendations.

## Dependencies
- **numpy** — required by the model.
- **openpyxl** — only needed if you run `health_score_model.py` as main (demo that reads `SampleRHR.xlsx`). Not needed for the web tester.

## File roles
| File | Role |
|------|------|
| `health_score_model.py` | Scoring logic: national/personal baselines, clinical zones, 40% absolute + 60% personal blend, mood-based weight personalisation, 3-day EMA, recommendations. |
| `health_score_tester.py` | Built-in HTTP server + single-page HTML/JS UI. |

## Design choices (so far)
- **Cold start**: &lt;14 days → national baselines (age/gender stratified). ≥14 days → rolling personal baseline.
- **Scoring**: Each metric = 40% clinical zone + 60% personal (sigmoid around mood-informed target). Final score = 3-day EMA.
- **Mood**: Shifts “optimal” targets toward high-mood days; metric weights adapt by correlation with mood over time.
- **Categories**: recovery (sleep), activity (steps, exercise), cardiovascular (RHR), stability (placeholder).

## Possible next steps
- Add a `requirements.txt` (e.g. `numpy`, optional `openpyxl`).
- Make the Excel path in `health_score_model.py` demo configurable or optional so it runs without a local file.
- Persist profile/history (e.g. JSON file or DB) so it survives server restart.
- Add simple tests (e.g. known inputs → expected score range).

---
*Last updated: Mar 2025*
