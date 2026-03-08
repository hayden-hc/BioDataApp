"""
TallyWell Flask API
───────────────────
Wraps health_score_model.py in a simple REST API for the iOS app.

Run locally (hackathon mode — same WiFi as iPhone):
    pip install flask numpy
    python api.py

Find your Mac's local IP:
    System Preferences → Network → WiFi → IP Address (e.g. 192.168.1.42)

iPhone calls:
    http://192.168.1.42:5001/score   ← POST daily data
    http://192.168.1.42:5001/history ← GET all scores for a user
    http://192.168.1.42:5001/reset   ← DELETE user session (dev only)
"""

from flask import Flask, request, jsonify
from health_score_model import HealthScoreModel
import threading

app = Flask(__name__)

# ─────────────────────────────────────────────
# In-memory session store
# key: user_id (string)  value: HealthScoreModel instance
# Fine for a hackathon — resets when server restarts
# ─────────────────────────────────────────────
_sessions: dict[str, HealthScoreModel] = {}
_lock = threading.Lock()


def get_or_create_model(user_id: str, profile: dict) -> HealthScoreModel:
    """Return existing model for user, or create one from profile."""
    with _lock:
        if user_id not in _sessions:
            _sessions[user_id] = HealthScoreModel(
                height_cm = profile["height_cm"],
                weight_kg = profile["weight_kg"],
                gender    = profile["gender"],
                age       = int(profile["age"]),
            )
        return _sessions[user_id]


# ─────────────────────────────────────────────
# POST /score
# ─────────────────────────────────────────────
# Body (JSON):
# {
#   "user_id": "abc123",
#   "profile": { "height_cm": 175, "weight_kg": 70, "gender": "male", "age": 28 },
#   "steps": 8432,
#   "exercise_minutes": 28,
#   "sleep_hours": 7.2,
#   "resting_hr": 61.0,    ← optional
#   "mood": 7,             ← 0–10
#   "date": "2026-03-07"   ← optional; if this date already exists, replace that day; else append
# }
#
# Returns:
# {
#   "score": 74.3,          ← smoothed 0–100
#   "score_raw": 72.1,
#   "category_scores": { "recovery": 80.1, "activity": 65.2, ... },
#   "metric_scores":   { "sleep_hours": 82.0, "steps": 60.1, ... },
#   "recommendations": ["Sleep is 0.8h below your baseline...", ...],
#   "baseline_source": "national" | "personal",
#   "days_of_data": 3,
#   "weights": { "category_weights": {...}, "metric_weights": {...} }
# }
# ─────────────────────────────────────────────

@app.route("/score", methods=["POST"])
def score():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "No JSON body"}), 400

    # Validate required fields
    required = ["user_id", "profile", "steps", "exercise_minutes", "sleep_hours", "mood"]
    missing  = [f for f in required if f not in data]
    if missing:
        return jsonify({"error": f"Missing fields: {missing}"}), 400

    profile = data["profile"]
    profile_required = ["height_cm", "weight_kg", "gender", "age"]
    missing_profile  = [f for f in profile_required if f not in profile]
    if missing_profile:
        return jsonify({"error": f"Missing profile fields: {missing_profile}"}), 400

    try:
        model = get_or_create_model(data["user_id"], profile)
        date = data.get("date")  # optional "YYYY-MM-DD"; if present and that date exists, replace; else append
        result = model.log_day(
            steps            = float(data["steps"]),
            exercise_minutes = float(data["exercise_minutes"]),
            sleep_hours      = float(data["sleep_hours"]),
            mood             = float(data["mood"]),
            resting_hr       = float(data["resting_hr"]) if data.get("resting_hr") else None,
            date            = date,
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    return jsonify({
        "score":            result.score,
        "score_raw":        result.score_raw,
        "category_scores":  result.category_scores,
        "metric_scores":    result.metric_scores,
        "recommendations":  result.recommendations,
        "baseline_source":  result.baseline_source,
        "days_of_data":     result.days_of_data,
        "weights":          result.current_weights,
    })


# ─────────────────────────────────────────────
# POST /goals — return current target (goal) values for spider chart
# Body: { "user_id": "...", "profile": { "height_cm", "weight_kg", "gender", "age" } }
# Returns: { "goals": { "steps", "exercise_min", "sleep_hours", "resting_hr", "mood" } }
# ─────────────────────────────────────────────

@app.route("/goals", methods=["POST"])
def goals():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "No JSON body"}), 400
    for key in ["user_id", "profile"]:
        if key not in data:
            return jsonify({"error": f"Missing field: {key}"}), 400
    profile = data["profile"]
    for key in ["height_cm", "weight_kg", "gender", "age"]:
        if key not in profile:
            return jsonify({"error": f"Missing profile field: {key}"}), 400
    try:
        model = get_or_create_model(data["user_id"], profile)
        goals_dict = model.get_goals()
        return jsonify({"goals": goals_dict})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────────────────────────────
# GET /history/<user_id>
# Returns all daily scores logged so far
# ─────────────────────────────────────────────

@app.route("/history/<user_id>", methods=["GET"])
def history(user_id: str):
    with _lock:
        model = _sessions.get(user_id)
    if not model:
        return jsonify({"days": []}), 200

    days = []
    for i, (entry, score) in enumerate(zip(model.history, model.score_history)):
        days.append({
            "day":           i + 1,
            "score":         round(score, 1),
            "steps":         entry.steps,
            "exercise_min":  entry.exercise_min,
            "sleep_hours":   entry.sleep_hours,
            "resting_hr":    entry.resting_hr,
            "mood":          entry.mood,
        })

    return jsonify({"user_id": user_id, "days": days})


# ─────────────────────────────────────────────
# DELETE /reset/<user_id>   (dev/demo only)
# ─────────────────────────────────────────────

@app.route("/reset/<user_id>", methods=["DELETE"])
def reset(user_id: str):
    with _lock:
        removed = _sessions.pop(user_id, None)
    return jsonify({"reset": user_id, "existed": removed is not None})


# ─────────────────────────────────────────────
# GET /health   (ping)
# ─────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "sessions": len(_sessions)})


if __name__ == "__main__":
    print("\n🟢 TallyWell API running")
    print("   Find your Mac IP: System Preferences → Network → WiFi")
    print("   iPhone endpoint:  http://<your-mac-ip>:5001/score\n")
    app.run(host="0.0.0.0", port=5001, debug=True)
