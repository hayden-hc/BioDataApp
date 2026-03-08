"""
Health Score Tester — web UI
Run this file, then open http://localhost:8080 in your browser (or the Network URL printed on startup for LAN access).
"""

import sys, json, traceback, os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import webbrowser, threading, socket

# Use project root so "import health_score_model" works when run from this repo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import health_score_model as hsm

# ── State ─────────────────────────────────────────────────────────────────────
# Default profile used when loading training data (matches HTML defaults)
DEFAULT_PROFILE = {'height_cm': 172.7, 'weight_kg': 68.0, 'age': 18, 'gender': 'male'}
model   = None
# list of (date_str, inputs_dict, ScoreResult); date_str used for replace-by-date (app behaviour)
day_log = []


def _parse_csv_date(s):
    """Parse date from TrainingDataV1.csv (e.g. 12/9/25, 1/1/26) -> YYYY-MM-DD."""
    s = (s or '').strip()
    if not s:
        return None
    from datetime import datetime
    for fmt in ('%m/%d/%y', '%m/%d/%Y', '%Y-%m-%d'):
        try:
            return datetime.strptime(s, fmt).strftime('%Y-%m-%d')
        except ValueError:
            continue
    return None


def _training_csv_path():
    """Resolve path to TrainingDataV1.csv. Search by name (case-insensitive) in script dir and cwd."""
    target_name_lower = 'trainingdatav1.csv'
    script_dir = os.path.dirname(os.path.abspath(os.path.realpath(__file__)))
    cwd = os.getcwd()

    def find_in_dir(d):
        if not d or not os.path.isdir(d):
            return None
        try:
            for name in os.listdir(d):
                if name.lower() == target_name_lower:
                    p = os.path.join(d, name)
                    if os.path.isfile(p):
                        return p
        except OSError:
            pass
        return None

    # 1) Script's directory (where this .py file lives)
    p = find_in_dir(script_dir)
    if p:
        return p
    # 2) Exact path in script dir (in case listdir differs from filesystem)
    p = os.path.join(script_dir, 'TrainingDataV1.csv')
    if os.path.isfile(p):
        return p
    # 3) Current working directory (by name match)
    p = find_in_dir(cwd)
    if p:
        return p
    # 4) Cwd exact path
    p = os.path.join(cwd, 'TrainingDataV1.csv')
    if os.path.isfile(p):
        return p
    # 5) Walk up from cwd
    d = cwd
    for _ in range(5):
        p = find_in_dir(d)
        if p:
            return p
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    # 6) Parent of script dir
    parent_script = os.path.dirname(script_dir)
    if parent_script != script_dir:
        p = find_in_dir(parent_script)
        if p:
            return p
    return None


def load_training_data_v1():
    """Load TrainingDataV1.csv into model and day_log. Creates default model if needed."""
    global model, day_log
    csv_path = _training_csv_path()
    if not csv_path:
        script_dir = os.path.dirname(os.path.abspath(os.path.realpath(__file__)))
        cwd = os.getcwd()
        print("  TrainingDataV1.csv not found.")
        print("  Script directory:", script_dir)
        print("  Current directory:", cwd)
        print("  (File must be in one of these, or in a parent of current directory.)")
        return 0
    if model is None:
        model = hsm.HealthScoreModel(
            height_cm=DEFAULT_PROFILE['height_cm'],
            weight_kg=DEFAULT_PROFILE['weight_kg'],
            gender=DEFAULT_PROFILE['gender'],
            age=DEFAULT_PROFILE['age'],
        )
    day_log = []
    mood_default = 7.0
    count = 0
    with open(csv_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    if not lines or not lines[0].strip().lower().startswith('date'):
        return 0
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(',')]
        if len(parts) < 5:
            continue
        date_str = _parse_csv_date(parts[0])
        if not date_str:
            continue
        try:
            steps = float(parts[1])
            rhr = float(parts[2]) if parts[2] else None
            exercise = float(parts[3])
            sleep = float(parts[4])
        except (ValueError, IndexError):
            continue
        result = model.log_day(
            steps=steps,
            exercise_minutes=exercise,
            sleep_hours=sleep,
            mood=mood_default,
            resting_hr=rhr,
            date=date_str,
        )
        inp = {'steps': steps, 'exercise': exercise, 'sleep': sleep, 'rhr': rhr, 'mood': mood_default}
        day_log.append((date_str, inp, result))
        count += 1
    return count

# ── HTML page ─────────────────────────────────────────────────────────────────
HTML = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Health Score Tester</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: monospace; font-size: 13px; background: #1e1e1e; color: #d4d4d4; display: flex; flex-direction: column; height: 100vh; }
  h3 { color: #4ec9b0; font-size: 13px; margin-bottom: 8px; border-bottom: 1px solid #444; padding-bottom: 4px; }
  .main { display: flex; flex: 1; overflow: hidden; gap: 0; }
  .left { width: 280px; min-width: 280px; overflow-y: auto; padding: 12px; border-right: 1px solid #333; display: flex; flex-direction: column; gap: 14px; }
  .right { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
  .section { background: #252526; border-radius: 4px; padding: 10px; }
  label { display: block; margin-bottom: 6px; }
  label span { display: inline-block; width: 140px; color: #9cdcfe; }
  input[type=number], input[type=text] { width: 90px; background: #3c3c3c; border: 1px solid #555; color: #d4d4d4; padding: 3px 6px; border-radius: 3px; font-family: monospace; font-size: 13px; }
  input[type=range] { width: 120px; vertical-align: middle; }
  .mood-val { display: inline-block; width: 28px; text-align: center; color: #f0c040; font-weight: bold; }
  select { background: #3c3c3c; border: 1px solid #555; color: #d4d4d4; padding: 3px 6px; border-radius: 3px; font-family: monospace; font-size: 13px; }
  button { padding: 6px 14px; border: none; border-radius: 3px; font-family: monospace; font-size: 13px; cursor: pointer; margin-top: 2px; }
  .btn-primary { background: #0e639c; color: #fff; font-weight: bold; width: 100%; padding: 8px; }
  .btn-secondary { background: #3c3c3c; color: #d4d4d4; width: 100%; }
  .btn-reset { background: #6b2222; color: #f48771; width: 100%; }
  button:hover { filter: brightness(1.2); }
  #history { list-style: none; }
  #history li { padding: 5px 8px; cursor: pointer; border-radius: 3px; color: #9cdcfe; }
  #history li:hover { background: #2a2d2e; }
  #history li.selected { background: #094771; color: #fff; }
  #output { flex: 1; overflow-y: auto; padding: 16px; font-size: 13px; white-space: pre; line-height: 1.6; }
  #status { padding: 6px 14px; background: #333; font-size: 12px; border-top: 1px solid #444; }
  #status.ok  { color: #4ec9b0; }
  #status.err { color: #f48771; }
  .score-big { font-size: 28px; font-weight: bold; color: #f0c040; }
  .cat-bar { display: flex; align-items: center; gap: 8px; margin: 2px 0; }
  .bar-bg { flex: 1; height: 10px; background: #3c3c3c; border-radius: 5px; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 5px; background: #4ec9b0; transition: width 0.3s; }
  .lbl { width: 160px; color: #9cdcfe; }
  .val { width: 40px; text-align: right; color: #ce9178; }
  hr { border: none; border-top: 1px solid #444; margin: 10px 0; }
</style>
</head>
<body>
<div class="main">

  <!-- LEFT PANEL -->
  <div class="left">

    <div class="section">
      <h3>PROFILE</h3>
      <label><span>Height (cm)</span><input type="number" id="height" value="172.7" step="0.1"></label>
      <label><span>Weight (kg)</span><input type="number" id="weight" value="68.0" step="0.1"></label>
      <label><span>Age</span><input type="number" id="age" value="18"></label>
      <label><span>Gender</span>
        <select id="gender"><option value="male">Male</option><option value="female">Female</option></select>
      </label>
      <button class="btn-reset" onclick="doReset()">Set Profile / Reset</button>
    </div>

    <div class="section">
      <h3>DAILY INPUTS</h3>
      <label><span>Date (YYYY-MM-DD)</span><input type="date" id="date"></label>
      <label><span>Steps</span><input type="number" id="steps" value="8500"></label>
      <label><span>Exercise (min)</span><input type="number" id="exercise" value="35"></label>
      <label><span>Sleep (hrs)</span><input type="number" id="sleep" value="7.5" step="0.1"></label>
      <label><span>Resting HR (bpm)</span><input type="number" id="rhr" value="55"></label>
      <label>
        <span>Mood (0–10)</span>
        <input type="range" id="mood" min="0" max="10" step="0.5" value="7"
               oninput="document.getElementById('mood_val').textContent=this.value">
        <span class="mood-val" id="mood_val">7</span>
      </label>
      <button class="btn-primary" onclick="doLog()">Log Day →</button>
      <button class="btn-secondary" onclick="doDefaults()" style="margin-top:6px">Fill Defaults</button>
      <button class="btn-secondary" onclick="doLoadTraining()" style="margin-top:6px">Load Training Data (TrainingDataV1.csv)</button>
      <p style="margin-top:8px;color:#888;font-size:11px">Same date = replace (like app Save/Refresh). New date = append.</p>
    </div>

    <div class="section" style="flex:1">
      <h3>HISTORY</h3>
      <ul id="history"></ul>
    </div>

  </div>

  <!-- RIGHT PANEL -->
  <div class="right">
    <div id="output">Set a profile and log days to see output.</div>
    <div id="status" class="ok">Ready.</div>
  </div>

</div>

<script>
function val(id) { return document.getElementById(id).value; }
function setStatus(msg, err=false) {
  const s = document.getElementById('status');
  s.textContent = msg;
  s.className = err ? 'err' : 'ok';
}

async function doReset() {
  const res = await fetch('/reset', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({
      height: parseFloat(val('height')),
      weight: parseFloat(val('weight')),
      age: parseInt(val('age')),
      gender: val('gender')
    })
  });
  const d = await res.json();
  if (d.error) { setStatus(d.error, true); return; }
  document.getElementById('history').innerHTML = '';
  document.getElementById('output').innerHTML = 'Profile set. Log a day to begin.';
  setStatus(d.message);
}

async function doLog() {
  const dateVal = val('date');
  const res = await fetch('/log', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({
      date: dateVal || null,
      steps: parseFloat(val('steps')),
      exercise: parseFloat(val('exercise')),
      sleep: parseFloat(val('sleep')),
      rhr: parseFloat(val('rhr')) || null,
      mood: parseFloat(val('mood'))
    })
  });
  const d = await res.json();
  if (d.error) { setStatus(d.error, true); return; }
  refreshHistory(d.history);
  renderOutput(d);
  if (d.replaced) {
    setStatus(`Date ${d.date} updated — score ${d.score.toFixed(1)} (raw ${d.score_raw.toFixed(1)})`);
  } else {
    setStatus(`Date ${d.date} added — score ${d.score.toFixed(1)} (raw ${d.score_raw.toFixed(1)})`);
  }
}

function doDefaults() {
  document.getElementById('steps').value    = 8500;
  document.getElementById('exercise').value = 35;
  document.getElementById('sleep').value    = 7.5;
  document.getElementById('rhr').value      = 55;
  document.getElementById('mood').value     = 7;
  document.getElementById('mood_val').textContent = 7;
}

function setDefaultDate() {
  const d = new Date();
  const y = d.getFullYear(), m = String(d.getMonth()+1).padStart(2,'0'), day = String(d.getDate()).padStart(2,'0');
  const el = document.getElementById('date');
  if (el && !el.value) el.value = y + '-' + m + '-' + day;
}

function refreshHistory(history) {
  const ul = document.getElementById('history');
  ul.innerHTML = '';
  (history || []).forEach((h, i) => {
    const li = document.createElement('li');
    const label = h.date || ('Day ' + (i+1));
    li.textContent = label + '  →  ' + (h.score != null ? h.score.toFixed(1) : '—');
    li.dataset.index = i;
    li.onclick = () => selectDay(i, li);
    ul.appendChild(li);
  });
}

function addToHistory(dateLabel, score, index) {
  const li = document.createElement('li');
  li.textContent = (dateLabel || ('Day ' + (index+1))) + '  →  ' + (score != null ? score.toFixed(1) : '—');
  li.dataset.index = index;
  li.onclick = () => selectDay(index, li);
  document.getElementById('history').appendChild(li);
  document.querySelectorAll('#history li').forEach(x => x.classList.remove('selected'));
  li.classList.add('selected');
}

async function selectDay(index, li) {
  document.querySelectorAll('#history li').forEach(x => x.classList.remove('selected'));
  li.classList.add('selected');
  const res = await fetch(`/day?index=${index}`);
  const d = await res.json();
  if (d.error) { setStatus(d.error, true); return; }
  renderOutput(d);
}

function bar(label, value, max=100) {
  const pct = Math.max(0, Math.min(100, value/max*100)).toFixed(1);
  const color = value >= 70 ? '#4ec9b0' : value >= 50 ? '#f0c040' : '#f48771';
  return `<div class="cat-bar">
    <span class="lbl">${label}</span>
    <div class="bar-bg"><div class="bar-fill" style="width:${pct}%;background:${color}"></div></div>
    <span class="val">${value.toFixed(1)}</span>
  </div>`;
}

function renderOutput(d) {
  let h = '';
  h += `<b style="color:#4ec9b0">${d.date ? 'DATE ' + d.date : 'DAY ' + d.day}</b>  <span style="color:#888">(${d.baseline} baseline)</span>\\n\\n`;
  h += `<span class="score-big">${d.score.toFixed(1)}</span> <span style="color:#888">/ 100</span>  `;
  h += `<span style="color:#888; font-size:11px">raw ${d.score_raw.toFixed(1)}</span>\\n\\n`;

  h += `<b style="color:#ce9178">CATEGORIES</b>\\n`;
  for (const [cat, s] of Object.entries(d.category_scores)) {
    const w = d.weights.category_weights[cat] || 0;
    h += bar(`  ${cat} (${(w*100).toFixed(0)}%)`, s);
  }

  h += `\\n<b style="color:#ce9178">METRIC SCORES</b>\\n`;
  for (const [m, s] of Object.entries(d.metric_scores)) {
    h += bar(`  ${m}`, s);
  }

  h += `\\n<b style="color:#ce9178">METRIC WEIGHTS</b>\\n`;
  for (const [m, w] of Object.entries(d.weights.metric_weights)) {
    const base = d.base_weights[m];
    const diff = w - base;
    const arrow = diff > 0.02 ? ' ↑' : diff < -0.02 ? ' ↓' : '  ';
    h += `  <span style="color:#9cdcfe;display:inline-block;width:160px">${m}</span>`;
    h += `<span style="color:#f0c040">${w.toFixed(3)}</span>${arrow}  `;
    h += `<span style="color:#666">base ${base.toFixed(3)}</span>\\n`;
  }

  h += `\\n<b style="color:#ce9178">INPUTS</b>\\n`;
  h += `  date ${d.date || '—'}  steps ${d.inputs.steps}  exercise ${d.inputs.exercise}min  sleep ${d.inputs.sleep}h  `;
  h += `rhr ${d.inputs.rhr || '—'}bpm  mood ${d.inputs.mood}/10\\n`;

  h += `\\n<b style="color:#ce9178">RECOMMENDATIONS</b>\\n`;
  for (const rec of d.recommendations) {
    h += `  • ${rec}\\n`;
  }

  document.getElementById('output').innerHTML = h;
}

async function loadInitialHistory() {
  try {
    const res = await fetch('/history');
    const history = await res.json();
    if (Array.isArray(history) && history.length > 0) {
      refreshHistory(history);
      setStatus('Loaded ' + history.length + ' days from training data. Click a day or log a new one.');
      const lastIdx = history.length - 1;
      const dayRes = await fetch('/day?index=' + lastIdx);
      const d = await dayRes.json();
      if (!d.error) renderOutput(d);
      document.querySelectorAll('#history li').forEach((x, i) => { x.classList.toggle('selected', i === lastIdx); });
    } else {
      setDefaultDate();
      setStatus('No history. Click "Load Training Data" or set profile and log a day.');
    }
  } catch (e) {
    setDefaultDate();
    setStatus('Could not load history. Click "Load Training Data" to load TrainingDataV1.csv.');
  }
}

async function doLoadTraining() {
  try {
    const res = await fetch('/load_training', { method: 'POST' });
    const d = await res.json();
    if (d.error) { setStatus(d.error, true); return; }
    const history = d.history || [];
    refreshHistory(history);
    if (history.length > 0) {
      setStatus('Loaded ' + history.length + ' days from TrainingDataV1.csv.');
      const lastIdx = history.length - 1;
      const dayRes = await fetch('/day?index=' + lastIdx);
      const dayData = await dayRes.json();
      if (!dayData.error) renderOutput(dayData);
      document.querySelectorAll('#history li').forEach((x, i) => { x.classList.toggle('selected', i === lastIdx); });
    } else {
      setStatus(d.message || 'No rows loaded. Is TrainingDataV1.csv next to the script?');
    }
  } catch (e) {
    setStatus('Failed to load training data: ' + e.message, true);
  }
}
document.addEventListener('DOMContentLoaded', function() {
  setDefaultDate();
  loadInitialHistory();
});
</script>
</body>
</html>"""

# ── HTTP handler ──────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):

    def log_message(self, *args): pass  # silence request logs

    def send_json(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/':
            body = HTML.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', len(body))
            self.end_headers()
            self.wfile.write(body)

        elif path == '/day':
            qs = parse_qs(urlparse(self.path).query)
            idx = int(qs.get('index', [0])[0])
            if idx >= len(day_log):
                self.send_json({'error': 'Day not found'})
                return
            date_str, inp, r = day_log[idx]
            self.send_json(result_to_dict(date_str, inp, r, idx))

        elif path == '/history':
            self.send_json([{'date': t[0], 'score': t[2].score} for t in day_log])

        else:
            self.send_response(404); self.end_headers()

    def do_POST(self):
        global model, day_log
        length = int(self.headers.get('Content-Length', 0))
        raw = self.rfile.read(length)
        body = json.loads(raw) if raw else {}
        path = urlparse(self.path).path

        if path == '/reset':
            try:
                model   = hsm.HealthScoreModel(
                    height_cm = body['height'],
                    weight_kg = body['weight'],
                    gender    = body['gender'],
                    age       = body['age'],
                )
                day_log = []
                g = body['gender']
                self.send_json({'message':
                    f"Profile set — {g}, {body['height']}cm, {body['weight']}kg, age {body['age']} | BMR: {model.bmr:.0f} kcal"
                })
            except Exception:
                self.send_json({'error': traceback.format_exc().splitlines()[-1]})

        elif path == '/load_training':
            try:
                n = load_training_data_v1()
                history = [{'date': t[0], 'score': t[2].score} for t in day_log]
                self.send_json({'history': history, 'message': f'Loaded {n} days.' if n else 'No CSV found or no rows loaded.'})
            except Exception:
                self.send_json({'error': traceback.format_exc().splitlines()[-1], 'history': []})

        elif path == '/log':
            if model is None:
                self.send_json({'error': 'Set profile first.'}); return
            try:
                date_str = (body.get('date') or '').strip() or None
                result = model.log_day(
                    steps            = body['steps'],
                    exercise_minutes = body['exercise'],
                    sleep_hours      = body['sleep'],
                    mood             = body['mood'],
                    resting_hr       = body.get('rhr'),
                    date            = date_str,
                )
                inp = {k: body.get(k) for k in ('steps', 'exercise', 'sleep', 'rhr', 'mood')}
                if date_str:
                    idx = next((i for i, t in enumerate(day_log) if t[0] == date_str), None)
                    if idx is not None:
                        day_log[idx] = (date_str, inp, result)
                        out = result_to_dict(date_str, inp, result, idx)
                        out['replaced'] = True
                        out['history'] = [{'date': t[0], 'score': t[2].score} for t in day_log]
                        self.send_json(out)
                        return
                date_display = date_str or f"Day {len(day_log) + 1}"
                day_log.append((date_display, inp, result))
                out = result_to_dict(date_display, inp, result, len(day_log) - 1)
                out['replaced'] = False
                out['history'] = [{'date': t[0], 'score': t[2].score} for t in day_log]
                self.send_json(out)
            except Exception:
                self.send_json({'error': traceback.format_exc().splitlines()[-1]})


def result_to_dict(date_str, inp, r, index):
    base_weights = {k: v[1] for k, v in hsm.BASE_METRIC_WEIGHTS.items()}
    return {
        'index':          index,
        'date':           date_str,
        'day':            r.days_of_data,
        'score':          r.score,
        'score_raw':      r.score_raw,
        'baseline':       r.baseline_source,
        'category_scores':r.category_scores,
        'metric_scores':  r.metric_scores,
        'weights':        r.current_weights,
        'base_weights':   base_weights,
        'recommendations':r.recommendations,
        'inputs':         inp,
    }

# ── Launch ────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    import os
    PORT = int(os.environ.get('PORT', 8080))
    n = load_training_data_v1()
    if n:
        print(f"  Loaded TrainingDataV1.csv: {n} days in history.")
    server = HTTPServer(('0.0.0.0', PORT), Handler)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = '127.0.0.1'
    print(f"  Local:   http://localhost:{PORT}")
    print(f"  Network: http://{local_ip}:{PORT}  ← share this with others on the same Wi-Fi")
    threading.Timer(0.5, lambda: webbrowser.open(f'http://localhost:{PORT}')).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopped.")
