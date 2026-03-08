# BioData App — Libraries & Frameworks

Libraries and frameworks used in the project, grouped by category.

---

## Charts & visualization

| Library    | Platform | Where used | Purpose |
|-----------|----------|------------|---------|
| **Swift Charts** | iOS | `ContentView.swift` | Line charts, heat map (score over time), correlation graph (parameter vs time). |

---

## UI

| Library / framework | Platform | Where used | Purpose |
|--------------------|----------|------------|---------|
| **SwiftUI** | iOS | `ContentView.swift`, `BioDataAppApp.swift` | All app screens: Score tab, Data tab, Correlation tab, Settings; navigation, forms, layout. |
| **HTML / CSS / JavaScript** | Web | `health_score_tester.py` (embedded) | Tester UI: profile form, daily inputs, history list, score output (no external front-end libs). |

---

## Machine learning & data science

| Library | Platform | Where used | Purpose |
|---------|----------|------------|---------|
| **NumPy** | Python | `health_score_model.py` | Linear algebra for Bayesian linear regression, OLS, design matrices, covariance; z-scores and normalization. |

---

## API & networking

| Library | Platform | Where used | Purpose |
|---------|----------|------------|---------|
| **Flask** | Python | `api.py` | REST API: `/score`, `/history`, `/reset`, `/health` for the iOS app. |
| **Foundation** (URLSession, etc.) | iOS | `TallyWellAPI.swift` | HTTP requests to the local Python API (POST score, GET history, health check). |

---

## Health & system

| Library / framework | Platform | Where used | Purpose |
|--------------------|----------|------------|---------|
| **HealthKit** | iOS | `HealthBridge.swift` | Read steps, resting heart rate, exercise minutes, sleep from Apple Health; authorization and background delivery. |

---

## Standard library / built-in

### Python

| Module | Where used | Purpose |
|--------|------------|---------|
| `csv` | `health_score_model.py` | (Available for CSV I/O; app uses custom logic.) |
| `os` | `health_score_model.py`, `health_score_tester.py` | Paths, file checks, `listdir` for finding `TrainingDataV1.csv`. |
| `sys` | `health_score_tester.py` | `sys.path` for importing `health_score_model`. |
| `json` | `health_score_tester.py` | Request/response JSON. |
| `traceback` | `health_score_tester.py` | Error messages in API responses. |
| `threading` | `api.py`, `health_score_tester.py` | Session lock (API); server runs in main thread. |
| `socket` | `health_score_tester.py` | Local IP detection for LAN URL. |
| `webbrowser` | `health_score_tester.py` | Open tester in browser on startup. |
| `urllib.parse` | `health_score_tester.py` | `parse_qs`, `urlparse` for request path/query. |
| `http.server` | `health_score_tester.py` | `HTTPServer`, `BaseHTTPRequestHandler` for tester. |
| `dataclasses` | `health_score_model.py` | `dataclass` for `DailyEntry`, `ScoreResult`, etc. |
| `typing` | `health_score_model.py` | `Optional`, `List`, `Tuple`, `Any` type hints. |
| `datetime` | `health_score_tester.py` | Parsing CSV dates (`strptime` / `strftime`). |

### Swift / iOS

| Framework / module | Where used | Purpose |
|-------------------|------------|---------|
| **Foundation** | `TallyWellAPI.swift`, `HealthBridge.swift`, `AppSettings.swift` | `URLSession`, `UserDefaults`, `DateFormatter`, `FileManager`, encoding, etc. |
| **SwiftUI** | App-wide | Declarative UI (see UI section). |
| **Charts** | `ContentView.swift` | Charts (see Charts section). |
| **HealthKit** | `HealthBridge.swift` | Health data (see Health section). |

---

## Summary by component

- **iOS app (Xcode):** SwiftUI, Charts, Foundation, HealthKit. No third-party Swift packages.
- **Python API:** Flask, NumPy. Install with: `pip install flask numpy`.
- **Tester (web):** Python stdlib only (`http.server`, `json`, `urllib`, etc.); no separate front-end stack.
