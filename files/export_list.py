# -*- coding: utf-8 -*-
"""
安全微伴刷课 · 学习清单导出
从日志还原课程列表，输出 xlsx。

用法：
    python export_list.py --logs <日志目录> --out <输出.xlsx>
"""
import argparse
import glob
import os
import re
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

RE_STUDY = re.compile(r"学习：\s*(.+)$")
RE_DONE = re.compile(r"^(.+?)\s+完成$")
RE_SKIP = re.compile(r"^(.+?)：(.+?)，跳过本门课程")
RE_Q = re.compile(r"课后习题\s+(\d+)\s+道")
RE_TS = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")
RE_COURSE = re.compile(r"^必修课\s+(.+)$")


def parse(logs_root):
    files = sorted(
        glob.glob(os.path.join(logs_root, "**", "weban-*.log"), recursive=True),
        key=os.path.basename,
    )
    # 只取 data/logs 根下的主日志，跳过账号子目录里的重复文件
    main_logs = [f for f in files if os.path.dirname(f).rstrip("\\").lower().endswith("logs")]
    if not main_logs:
        main_logs = files

    courses = {}
    order = []
    cur = None

    for path in main_logs:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
        except OSError:
            continue

        for ln in lines:
            parts = ln.split("|")
            if len(parts) < 4:
                continue
            ts, msg = parts[0], "|".join(parts[3:])
            m = RE_TS.match(ts)
            ts = m.group(1) if m else ts

            m = RE_STUDY.search(msg)
            if m:
                p = m.group(1).strip()
                cur = p
                if p not in courses:
                    courses[p] = {"status": "开始学习", "done_at": "", "questions": "", "note": ""}
                    order.append(p)
                continue

            body = msg.strip()
            m = RE_COURSE.match(body)
            if not m:
                continue
            rest = m.group(1)

            md = RE_DONE.match(rest)
            if md and "SUCCESS" in ln:
                p = md.group(1).strip()
                if p not in courses:
                    courses[p] = {"status": "", "done_at": "", "questions": "", "note": ""}
                    order.append(p)
                courses[p]["status"] = "已完成"
                courses[p]["done_at"] = ts
                cur = p
                continue

            ms = RE_SKIP.match(rest)
            if ms:
                p = ms.group(1).strip()
                if p not in courses:
                    courses[p] = {"status": "", "done_at": "", "questions": "", "note": ""}
                    order.append(p)
                courses[p]["status"] = "跳过"
                courses[p]["note"] = ms.group(2).strip()[:120]
                continue

            mq = RE_Q.search(body)
            if mq and cur and cur in courses:
                courses[cur]["questions"] = f"{mq.group(1)} 道"

    rows = []
    for i, p in enumerate(order, 1):
        c = courses[p]
        seg = p.split("/")
        project = seg[0] if len(seg) > 0 else ""
        category = seg[1] if len(seg) > 1 else ""
        name = "/".join(seg[2:]) if len(seg) > 2 else p
        rows.append([i, project, category, name, c["status"], c["questions"] or "无", c["done_at"], c["note"]])
    return rows


def build_xlsx(rows, out_path):
    wb = Workbook()
    ws = wb.active
    ws.title = "学习清单"

    headers = ["序号", "项目", "分类", "课程名称", "状态", "课后习题", "完成时间", "备注"]
    ws.append(headers)

    head_fill = PatternFill("solid", fgColor="2B4C7E")
    head_font = Font(color="FFFFFF", bold=True, size=11)
    thin = Side(style="thin", color="D5DCE8")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)

    for col in range(1, len(headers) + 1):
        cell = ws.cell(row=1, column=col)
        cell.fill = head_fill
        cell.font = head_font
        cell.alignment = Alignment(horizontal="center", vertical="center")
        cell.border = border

    ok_fill = PatternFill("solid", fgColor="E8F5EC")
    skip_fill = PatternFill("solid", fgColor="FDE9E9")
    q_fill = PatternFill("solid", fgColor="FFF6E0")

    for r in rows:
        ws.append(r)

    for ri in range(2, ws.max_row + 1):
        status = ws.cell(row=ri, column=5).value
        questions = ws.cell(row=ri, column=6).value
        for ci in range(1, len(headers) + 1):
            cell = ws.cell(row=ri, column=ci)
            cell.border = border
            cell.alignment = Alignment(
                vertical="center",
                horizontal="center" if ci in (1, 5, 6, 7) else "left",
                wrap_text=(ci in (3, 4, 8)),
            )
            if status == "跳过":
                cell.fill = skip_fill
            elif status == "已完成":
                cell.fill = ok_fill
        if questions and questions != "无":
            ws.cell(row=ri, column=6).fill = q_fill

    for i, w in enumerate([6, 34, 18, 46, 10, 10, 20, 40], 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:H{ws.max_row}"

    # 汇总页
    ws2 = wb.create_sheet("汇总")
    total = len(rows)
    done = sum(1 for r in rows if r[4] == "已完成")
    skip = sum(1 for r in rows if r[4] == "跳过")
    q_courses = sum(1 for r in rows if r[5] and r[5] != "无")
    q_total = sum(int(re.sub(r"\D", "", r[5]) or 0) for r in rows if r[5] and r[5] != "无")

    times = [r[6] for r in rows if r[6]]
    summary = [
        ["统计项", "数值"],
        ["导出时间", datetime.now().strftime("%Y-%m-%d %H:%M:%S")],
        ["日志起始", min(times) if times else "-"],
        ["日志末尾", max(times) if times else "-"],
        ["课程总数（日志中出现）", total],
        ["已完成", done],
        ["跳过（网络异常）", skip],
        ["带课后习题的课程数", q_courses],
        ["课后习题总题数", q_total],
    ]
    for row in summary:
        ws2.append(row)
    for cell in ws2[1]:
        cell.fill = head_fill
        cell.font = head_font
        cell.alignment = Alignment(horizontal="center")
    ws2.column_dimensions["A"].width = 26
    ws2.column_dimensions["B"].width = 24

    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    wb.save(out_path)
    return {"total": total, "done": done, "skip": skip, "q_courses": q_courses, "q_total": q_total}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--logs", required=True, help="日志目录")
    ap.add_argument("--out", required=True, help="输出 xlsx 路径")
    args = ap.parse_args()

    if not os.path.isdir(args.logs):
        print(f"日志目录不存在: {args.logs}")
        raise SystemExit(1)

    rows = parse(args.logs)
    if not rows:
        print("日志里没有解析到课程记录")
        raise SystemExit(1)

    stat = build_xlsx(rows, args.out)
    print(f"已导出: {args.out}")
    print(f"课程 {stat['total']} 条 / 已完成 {stat['done']} / 跳过 {stat['skip']} / 带题课程 {stat['q_courses']} / 题数 {stat['q_total']}")


if __name__ == "__main__":
    main()
