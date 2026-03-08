# BioData App

iOS app (Xcode) that reads Apple Health data and can score it via a **local Python API** (TallyWell / `health_score_model`). Run the app on simulator or device; run the API on your Mac when you want the personalised score.

## Run the mobile app (Xcode)

1. Open `BioDataApp.xcodeproj` in Xcode.
2. Run on **Simulator** or a device.
3. In the app: **Settings** tab → set your **profile** (height, weight, age, gender) and **API base URL** (see below).
4. **Sync** tab → tap Sync. Health data is written to CSV; if the API is reachable, the ring shows the **TallyWell** (Python model) score and recommendations.

**API URL**

- **Simulator:** `http://localhost:5001`
- **Device (same Wi‑Fi as Mac):** `http://<your-mac-ip>:5001`  
  Find your Mac IP: **System Settings → Network → Wi‑Fi → Details** (e.g. `192.168.1.42`).

**Device + local API:** In Xcode, add an App Transport Security exception so the app can use `http` to your Mac: Target → **Info** → add **App Transport Security Settings** (Dictionary) → **Allow Local Networking** = **YES**. Or use the provided `BioDataApp/Info.plist` and set the target’s *Info.plist File* to it (you may need to re-add other keys from the generated plist).

## Run the Python API (when you want the model score)

On your Mac (same machine as Xcode, or any machine on the same network):

```bash
pip install flask numpy
python api.py
```

The API listens on **port 5001**. The app’s **Sync** sends today’s metrics + profile + mood to `POST /score` and shows the returned score and recommendations. If the API is not running or unreachable, the app falls back to the built‑in simple score and CSV-only data.

## Tester (optional)

`health_score_tester.py` is a small local web UI that talks to the **Python model** directly (no Flask). Run it when you want to try the model from a browser:

```bash
# From the project root, with health_score_model in the same directory:
python health_score_tester.py
# Then open http://localhost:8080
```

Fix the `sys.path` at the top of `health_score_tester.py` if your project path differs.
