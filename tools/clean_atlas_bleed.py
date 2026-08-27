# -*- coding: utf-8 -*-
"""清理角色图集 (all_actions_atlas.png) 中相邻帧溢出造成的杂点像素。

GameTool 动作整理台导出总图集时 drawImage 未按单元格裁剪，帧内容（靴尖、
剑尖等）超出 240x240 格子的部分会被画进相邻格子。表现为游戏内动画帧
顶部/侧边出现来自上/右帧的碎片。

判定规则（保守）：每个单元格内与主体不连通、且满足以下任一条件的孤立色块：
1. 面积 <= 300px 且被格子顶边或左右边截断（贴边）——上/右帧溢出的碎片；
2. 面积 <= 20px 且高度只有 1px 的横线残渣——上帧脚下浮尘溢入本格、
   与格顶隔着透明空隙时的残留（合法粒子至少 2px 高，不会被误删）。
合法内容（脚底贴地、大特效贴边、法系角色 2px 以上的光点粒子）不受影响。

用法:
    python tools/clean_atlas_bleed.py            # 清理全部角色
    python tools/clean_atlas_bleed.py qishi      # 只清理指定角色
"""
import os
import sys

from PIL import Image

CELL = 240
ALPHA_THRESHOLD = 10
MAX_STRAY_AREA = 300
MAX_TINY_AREA = 20


def find_components(px, x0, y0):
    seen = [[False] * CELL for _ in range(CELL)]
    comps = []
    for yy in range(CELL):
        for xx in range(CELL):
            if seen[xx][yy]:
                continue
            if px[x0 + xx, y0 + yy][3] <= ALPHA_THRESHOLD:
                seen[xx][yy] = True
                continue
            stack = [(xx, yy)]
            seen[xx][yy] = True
            pts = []
            while stack:
                cx, cy = stack.pop()
                pts.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1),
                               (1, 1), (1, -1), (-1, 1), (-1, -1)):
                    nx, ny = cx + dx, cy + dy
                    if (0 <= nx < CELL and 0 <= ny < CELL
                            and not seen[nx][ny]
                            and px[x0 + nx, y0 + ny][3] > ALPHA_THRESHOLD):
                        seen[nx][ny] = True
                        stack.append((nx, ny))
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            comps.append({"pts": pts, "n": len(pts),
                          "x0": min(xs), "y0": min(ys),
                          "x1": max(xs), "y1": max(ys)})
    return comps


def is_stray(comp, main):
    if comp is main:
        return False
    if comp["n"] <= MAX_TINY_AREA and comp["y1"] == comp["y0"]:
        return True
    if comp["n"] > MAX_STRAY_AREA:
        return False
    touches_top = comp["y0"] == 0
    touches_side = comp["x0"] == 0 or comp["x1"] == CELL - 1
    return touches_top or touches_side


def clean_atlas(path):
    im = Image.open(path).convert("RGBA")
    width, height = im.size
    px = im.load()
    removed = 0
    for row in range(height // CELL):
        for col in range(width // CELL):
            comps = find_components(px, col * CELL, row * CELL)
            if not comps:
                continue
            main = max(comps, key=lambda c: c["n"])
            for comp in comps:
                if is_stray(comp, main):
                    for cx, cy in comp["pts"]:
                        px[col * CELL + cx, row * CELL + cy] = (0, 0, 0, 0)
                    removed += comp["n"]
    if removed:
        im.save(path)
    return removed


def main():
    chars_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "characters")
    targets = sys.argv[1:]
    for name in sorted(os.listdir(chars_dir)):
        if targets and name not in targets:
            continue
        path = os.path.join(chars_dir, name, "godot", "all_actions_atlas.png")
        if not os.path.exists(path):
            continue
        removed = clean_atlas(path)
        print(f"{name}: removed {removed} stray px" if removed else f"{name}: clean")


if __name__ == "__main__":
    main()
