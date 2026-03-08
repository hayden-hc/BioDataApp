"""
Health Score Tester — web UI
Run this file, then open http://localhost:8080 in your browser (or the Network URL printed on startup for LAN access).
"""

import sys, json, traceback
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import webbrowser, threading, socket

sys.path.insert(0, '/Users/nicholaske/Desktop/CS31/health app')
import health_score_model as hsm

# ── State ─────────────────────────────────────────────────────────────────────
model   = None
day_log = []   # list of (inputs_dict, ScoreResult)

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
      <label><span>Height</span>
        <input type="number" id="height" value="172.7" step="0.1" style="width:80px">
        <select id="height_unit"><option value="cm">cm</option><option value="in">in</option></select>
      </label>
      <label><span>Weight</span>
        <input type="number" id="weight" value="68.0" step="0.1" style="width:80px">
        <select id="weight_unit"><option value="kg">kg</option><option value="lb">lb</option></select>
      </label>
      <label><span>Age</span><input type="number" id="age" value="18"></label>
      <label><span>Gender</span>
        <select id="gender"><option value="male">Male</option><option value="female">Female</option></select>
      </label>
      <button class="btn-reset" onclick="doReset()">Set Profile / Reset</button>
    </div>

    <div class="section">
      <h3>DAILY INPUTS</h3>
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
  // Convert height/weight to cm/kg before sending (server expects SI units)
  const rawHeight = parseFloat(val('height'));
  const heightUnit = val('height_unit');
  const heightCm = (heightUnit === 'in') ? (rawHeight * 2.54) : rawHeight;

  const rawWeight = parseFloat(val('weight'));
  const weightUnit = val('weight_unit');
  const weightKg = (weightUnit === 'lb') ? (rawWeight * 0.45359237) : rawWeight;

  const res = await fetch('/reset', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({
      height: heightCm,
      weight: weightKg,
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
  const res = await fetch('/log', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({
      steps: parseFloat(val('steps')),
      exercise: parseFloat(val('exercise')),
      sleep: parseFloat(val('sleep')),
      rhr: parseFloat(val('rhr')) || null,
      mood: parseFloat(val('mood'))
    })
  });
  const d = await res.json();
  if (d.error) { setStatus(d.error, true); return; }
  addToHistory(d.day, d.score, d.index);
  renderOutput(d);
  setStatus(`Day ${d.day} logged — score ${d.score.toFixed(1)} (raw ${d.score_raw.toFixed(1)})`);
}

function doDefaults() {
  document.getElementById('steps').value    = 8500;
  document.getElementById('exercise').value = 35;
  document.getElementById('sleep').value    = 7.5;
  document.getElementById('rhr').value      = 55;
  document.getElementById('mood').value     = 7;
  document.getElementById('mood_val').textContent = 7;
  // keep profile defaults in SI units
  document.getElementById('height').value = 172.7;
  document.getElementById('height_unit').value = 'cm';
  document.getElementById('weight').value = 68.0;
  document.getElementById('weight_unit').value = 'kg';
}

function addToHistory(day, score, index) {
  const li = document.createElement('li');
  li.textContent = `Day ${String(day).padStart(3)}  →  ${score.toFixed(1)}`;
  li.dataset.index = index;
  li.onclick = () => selectDay(index, li);
  document.getElementById('history').appendChild(li);
  // auto-select
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
  h += `<b style="color:#4ec9b0">DAY ${d.day}</b>  <span style="color:#888">(${d.baseline} baseline)</span>\\n\\n`;
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
  h += `  steps ${d.inputs.steps}  exercise ${d.inputs.exercise}min  sleep ${d.inputs.sleep}h  `;
  h += `rhr ${d.inputs.rhr || '—'}bpm  mood ${d.inputs.mood}/10\\n`;

  h += `\\n<b style="color:#ce9178">RECOMMENDATIONS</b>\\n`;
  for (const rec of d.recommendations) {
    h += `  • ${rec}\\n`;
  }

  document.getElementById('output').innerHTML = h;
}
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
            inp, r = day_log[idx]
            self.send_json(result_to_dict(inp, r, idx))

        else:
            self.send_response(404); self.end_headers()

    def do_POST(self):
        global model, day_log
        length = int(self.headers.get('Content-Length', 0))
        body   = json.loads(self.rfile.read(length))
        path   = urlparse(self.path).path

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

        elif path == '/log':
            if model is None:
                self.send_json({'error': 'Set profile first.'}); return
            try:
                result = model.log_day(
                    steps            = body['steps'],
                    exercise_minutes = body['exercise'],
                    sleep_hours      = body['sleep'],
                    mood             = body['mood'],
                    resting_hr       = body.get('rhr'),
                )
                inp = {k: body.get(k) for k in ('steps','exercise','sleep','rhr','mood')}
                day_log.append((inp, result))
                self.send_json(result_to_dict(inp, result, len(day_log)-1))
            except Exception:
                self.send_json({'error': traceback.format_exc().splitlines()[-1]})


def result_to_dict(inp, r, index):
    base_weights = {k: v[1] for k, v in hsm.BASE_METRIC_WEIGHTS.items()}
    return {
        'index':          index,
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
