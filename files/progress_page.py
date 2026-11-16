# -*- coding: utf-8 -*-
"""
安全微伴刷课 · 实时进度页
只读日志文件，不干扰刷课进程。

用法：
    python progress_page.py --logs <日志目录> [--port 8899]
然后浏览器访问 http://127.0.0.1:8899/
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

LOG_ROOT = ""
PORT = 8899

RE_PROGRESS = re.compile(
    r"进度：必修课 (\d+)/(\d+)，推送课 (\d+)/(\d+)，自选课 (\d+)/(\d+)，考试 (\d+)/(\d+)，预计剩余 (\S+)"
)
RE_STUDY = re.compile(r"学习：\s*(.+)$")
RE_DONE = re.compile(r"SUCCESS\|[^|]*\|(.+?)\s*完成$")
RE_VIDEO = re.compile(r"视频课程按 (\S+) 倍速对齐：等待 (\S+)（视频时长 (\S+)）")
RE_WAIT = re.compile(r"等待学习时长 (\S+) \(已用 (\S+)/(\S+)\)")
RE_CAPTCHA = re.compile(r"(自动识别.*|验证码.*)")
RE_TS = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")


def latest_log():
    files = glob.glob(os.path.join(LOG_ROOT, "**", "weban-*.log"), recursive=True)
    if not files:
        return None
    # 按文件名里的时间戳排序（文件被占用时 mtime 不刷新）
    return max(files, key=lambda p: os.path.basename(p))


def read_log(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def weban_running():
    try:
        out = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq python.exe", "/NH"],
            capture_output=True, text=True, encoding="gbk", errors="replace", timeout=6,
        ).stdout
        return "python.exe" in out
    except Exception:
        return False


def build_status():
    path = latest_log()
    if not path:
        return {"ok": False, "error": "找不到日志文件，先跑一次刷课"}

    text = read_log(path)
    lines = [ln for ln in text.splitlines() if ln.strip()]

    done_required = total_required = 0
    push_done = push_total = 0
    opt_done = opt_total = 0
    exam_done = exam_total = 0
    eta = "--"
    current = "--"
    last_ts = None
    questions = 0

    for ln in lines:
        m = RE_PROGRESS.search(ln)
        if m:
            done_required, total_required = int(m.group(1)), int(m.group(2))
            push_done, push_total = int(m.group(3)), int(m.group(4))
            opt_done, opt_total = int(m.group(5)), int(m.group(6))
            exam_done, exam_total = int(m.group(7)), int(m.group(8))
            eta = m.group(9)

        m = RE_STUDY.search(ln)
        if m:
            current = m.group(1).strip()

        m = RE_TS.match(ln)
        if m:
            last_ts = m.group(1)

        if re.search(r"课后习题\s+(\d+)\s+道", ln):
            questions += 1

    percent = (done_required / total_required * 100) if total_required else 0.0

    recent = lines[-14:]
    recent = [re.sub(r"^\d{4}-\d{2}-\d{2} ", "", x) for x in recent]

    return {
        "ok": True,
        "running": weban_running(),
        "percent": round(percent, 1),
        "done": done_required,
        "total": total_required,
        "push": [push_done, push_total],
        "opt": [opt_done, opt_total],
        "exam": [exam_done, exam_total],
        "eta": eta,
        "current": current,
        "questions": questions,
        "last_ts": last_ts,
        "recent": recent,
        "log_file": os.path.basename(path),
        "server_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }


HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>安全微伴 · 刷课进度</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{
    min-height:100vh;
    background:radial-gradient(1200px 600px at 15% 0%,#1b2a4a 0%,#0a0f1c 55%,#06090f 100%);
    color:#e8eefc;
    font-family:"Microsoft YaHei UI","Microsoft YaHei",-apple-system,"Segoe UI",sans-serif;
    padding:38px 22px 60px;
  }
  .wrap{max-width:900px;margin:0 auto}
  .head{display:flex;align-items:baseline;gap:14px;flex-wrap:wrap;margin-bottom:6px}
  h1{font-size:22px;font-weight:600;letter-spacing:.5px}
  .sub{color:#7f8fa8;font-size:13px}
  .badge{
    display:inline-flex;align-items:center;gap:7px;
    padding:5px 13px;border-radius:999px;font-size:12.5px;font-weight:600;
    border:1px solid rgba(120,220,180,.35);
    background:rgba(46,204,150,.10);color:#7ef0bb;margin-left:auto;
  }
  .badge.off{border-color:rgba(255,120,120,.35);background:rgba(255,80,80,.10);color:#ff9a9a}
  .dot{width:8px;height:8px;border-radius:50%;background:#2ecc96;box-shadow:0 0 10px #2ecc96}
  .badge.off .dot{background:#ff6b6b;box-shadow:0 0 10px #ff6b6b}
  .card{
    background:linear-gradient(180deg,rgba(30,44,70,.72),rgba(18,26,44,.72));
    border:1px solid rgba(90,130,200,.20);
    border-radius:18px;padding:26px 26px 22px;margin-top:20px;
    box-shadow:0 18px 50px rgba(0,0,0,.35);
  }
  .big{display:flex;align-items:flex-end;gap:12px;margin-bottom:14px}
  .num{font-size:52px;font-weight:700;line-height:1;
       background:linear-gradient(135deg,#7ff0ff,#6ea8ff 60%,#b48cff);
       -webkit-background-clip:text;background-clip:text;color:transparent;
       font-variant-numeric:tabular-nums}
  .of{font-size:20px;color:#6d7f9c;padding-bottom:8px}
  .pct{margin-left:auto;font-size:17px;color:#8fa6c8;padding-bottom:10px;font-variant-numeric:tabular-nums}
  .bar{height:14px;border-radius:999px;background:rgba(255,255,255,.07);overflow:hidden;position:relative}
  .fill{
    height:100%;width:0%;border-radius:999px;
    background:linear-gradient(90deg,#3ad1ff,#6a8dff 55%,#b06bff);
    transition:width .8s cubic-bezier(.22,.61,.36,1);
    box-shadow:0 0 18px rgba(90,150,255,.55);
  }
  .bar::after{
    content:"";position:absolute;inset:0;
    background:linear-gradient(90deg,transparent,rgba(255,255,255,.22),transparent);
    animation:sweep 2.6s infinite;
  }
  @keyframes sweep{0%{transform:translateX(-100%)}100%{transform:translateX(100%)}}
  .now{margin-top:20px;padding:14px 16px;border-radius:12px;
       background:rgba(70,120,220,.10);border-left:3px solid #4d7dff}
  .now .lbl{font-size:11.5px;color:#7d90ad;letter-spacing:1px;margin-bottom:6px}
  .now .val{font-size:15.5px;color:#dce8ff;line-height:1.5;word-break:break-all}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-top:16px}
  .cell{padding:12px 14px;border-radius:11px;background:rgba(255,255,255,.035);
        border:1px solid rgba(120,160,220,.12)}
  .cell .k{font-size:11.5px;color:#7d90ad;margin-bottom:5px}
  .cell .v{font-size:16px;color:#cfe0ff;font-variant-numeric:tabular-nums}
  .log{margin-top:22px}
  .log .lbl{font-size:11.5px;color:#7d90ad;letter-spacing:1px;margin-bottom:10px}
  pre{
    background:rgba(0,0,0,.32);border:1px solid rgba(90,130,200,.14);
    border-radius:12px;padding:14px 16px;font-size:12px;line-height:1.65;
    color:#93a7c4;max-height:300px;overflow:auto;white-space:pre-wrap;word-break:break-all;
    font-family:"Cascadia Mono","Consolas",monospace;
  }
  .foot{margin-top:16px;color:#5f7291;font-size:11.5px;text-align:right}
</style>
</head>
<body>
<div class="wrap">
  <div class="head">
    <h1>安全微伴 · 刷课进度</h1>
    <span class="sub" id="logname">—</span>
    <span class="badge" id="state"><span class="dot"></span><span id="statetxt">读取中</span></span>
  </div>

  <div class="card">
    <div class="big">
      <span class="num" id="done">0</span>
      <span class="of" id="total">/ 0</span>
      <span class="pct" id="pct">0%</span>
    </div>
    <div class="bar"><div class="fill" id="fill"></div></div>

    <div class="now">
      <div class="lbl">正在学习</div>
      <div class="val" id="current">—</div>
    </div>

    <div class="grid">
      <div class="cell"><div class="k">预计剩余</div><div class="v" id="eta">—</div></div>
      <div class="cell"><div class="k">课后习题课程</div><div class="v" id="questions">—</div></div>
      <div class="cell"><div class="k">推送 / 自选</div><div class="v" id="extra">—</div></div>
      <div class="cell"><div class="k">考试</div><div class="v" id="exam">—</div></div>
      <div class="cell"><div class="k">最新日志时间</div><div class="v" id="lastts">—</div></div>
    </div>

    <div class="log">
      <div class="lbl">最近日志</div>
      <pre id="recent">加载中…</pre>
    </div>
    <div class="foot" id="foot">—</div>
  </div>
</div>

<script>
async function tick(){
  try{
    const r = await fetch('/api/status', {cache:'no-store'});
    const d = await r.json();
    if(!d.ok){ document.getElementById('statetxt').textContent = d.error || '读取失败'; return; }

    document.getElementById('done').textContent = d.done;
    document.getElementById('total').textContent = '/ ' + d.total;
    document.getElementById('pct').textContent = d.percent + '%';
    document.getElementById('fill').style.width = Math.min(100, d.percent) + '%';
    document.getElementById('current').textContent = d.current || '—';
    document.getElementById('eta').textContent = d.eta || '—';
    document.getElementById('questions').textContent = d.questions + ' 门';
    document.getElementById('extra').textContent = d.push[0]+'/'+d.push[1]+' · '+d.opt[0]+'/'+d.opt[1];
    document.getElementById('exam').textContent = d.exam[0]+'/'+d.exam[1];
    document.getElementById('lastts').textContent = d.last_ts || '—';
    document.getElementById('logname').textContent = d.log_file || '';
    document.getElementById('recent').textContent = (d.recent||[]).join('\n');
    document.getElementById('foot').textContent = '数据时间 ' + d.server_time + ' · 每 3 秒刷新';

    const badge = document.getElementById('state');
    if(d.running){
      badge.classList.remove('off');
      document.getElementById('statetxt').textContent = '运行中';
    }else{
      badge.classList.add('off');
      document.getElementById('statetxt').textContent = '已停止';
    }
  }catch(e){
    document.getElementById('statetxt').textContent = '连接断开';
  }
}
tick();
setInterval(tick, 3000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.startswith("/api/status"):
            body = json.dumps(build_status(), ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            body = HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


def main():
    global LOG_ROOT, PORT
    ap = argparse.ArgumentParser()
    ap.add_argument("--logs", required=True, help="日志目录")
    ap.add_argument("--port", type=int, default=8899, help="监听端口")
    args = ap.parse_args()

    LOG_ROOT = args.logs
    PORT = args.port

    if not os.path.isdir(LOG_ROOT):
        print(f"日志目录不存在: {LOG_ROOT}")
        sys.exit(1)

    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"进度页已启动: http://127.0.0.1:{PORT}/  (日志: {LOG_ROOT})")
    srv.serve_forever()


if __name__ == "__main__":
    main()
