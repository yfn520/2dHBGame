#!/usr/bin/env python3
"""headless 技能特效自动配置（库匹配优先 + 生成兜底，只产 bundle，不写 skills）。

管线与网页侧技能特效导演一致：
  1. 轨道策划：确定性预设（按技能语义）或 POST /skill-fx/plan（LLM）
  2. 搜库：POST /skill-fx/library/search（spine/unity/序列帧三源，已视觉打标）
  3. 取图集：GET 库返回的 preview_url（去掉 /api 前缀）→ PNG sheet；黑底源过 POST /skill-fx/visual/process 抠底
  4. 导出：POST /skill-fx/bundle/export → 返回 files[]（effect.tscn / attachment_meta.json / skill_fx_bundle.json），本脚本写盘
  5. play_effect 节点不写：由 Godot 技能节点配置里的「导入 AI 特效包」完成（单一导入器契约）

用法：
  python tools/configure_skill_fx.py --dry-run     # 只看搜库命中与分数
  python tools/configure_skill_fx.py               # 产出 qishi-6001~6004 四个 bundle
  python tools/configure_skill_fx.py --actors 7001 --backend http://localhost:8000
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from configure_skill_audio import build_action_context, load_json, sha16  # noqa: E402

PROJECT = Path(__file__).resolve().parent.parent          # hengban-2/
DATA = PROJECT / "data"
ACTORS_DIR = DATA / "skills" / "actors"
SKILL_FX_ROOT = PROJECT / "assets" / "effects" / "skill_fx"
SKILL_FX_RES_ROOT = "assets/effects/skill_fx"
BACKUP_ROOT = PROJECT / ".frame-ronin" / "backups" / "skill-fx"
# 网页编排台的 AI 特效 checkpoint 目录（前端 skillFxEditorStatePath 同约定）
WEB_STATE_ROOT = PROJECT / ".gametool" / "skill_fx_states"
WEB_STATE_BACKUP_ROOT = PROJECT / ".frame-ronin" / "backups" / "skill_fx_states"

STYLE = "2D side-scrolling fantasy game VFX"
TARGET_FRAMES = 8
TARGET_FRAME_SIZE = 256
# 库素材原生帧尺寸差异极大（从 85x33 到 400x400），scale=1 时小素材在 256px 角色旁几乎看不见。
# 按 phase 给出目标屏幕尺寸（px），用 scale 归一；TrackTransform.scale 合法区间 0.05~12。
PHASE_TARGET_SIZE = {"impact": 200.0, "release": 230.0, "area": 320.0, "projectile": 120.0,
                     "charge": 200.0, "attachment": 180.0, "buff": 200.0, "screen": 600.0}


def normalize_track_scale(track: dict, frame_w: int, frame_h: int) -> float:
    """按 phase 目标尺寸算出 scale，写回 track.transform.scale 并返回。"""
    target = PHASE_TARGET_SIZE.get(str(track.get("phase")), 200.0)
    longest = max(1.0, float(max(frame_w, frame_h)))
    scale = round(min(12.0, max(0.05, target / longest)), 3)
    track.setdefault("transform", {})["scale"] = scale
    return scale


# ===================== HTTP =====================

def http_json(url: str, payload: dict | None = None, timeout: int = 300) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_bytes(url: str, timeout: int = 180) -> bytes:
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return resp.read()


def http_multipart_png(url: str, fields: dict[str, str], files: list[tuple[str, str, bytes]], timeout: int = 300) -> bytes:
    """multipart/form-data POST：fields 为普通表单字段，files 为 (字段名, 文件名, 字节)。"""
    boundary = f"----frfx{uuid.uuid4().hex}"
    body = io.BytesIO()
    for key, value in fields.items():
        body.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n".encode("utf-8"))
    for field_name, file_name, content in files:
        body.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{field_name}\"; filename=\"{file_name}\"\r\n".encode("utf-8"))
        body.write(b"Content-Type: image/png\r\n\r\n")
        body.write(content)
        body.write(b"\r\n")
    body.write(f"--{boundary}--\r\n".encode("utf-8"))
    req = urllib.request.Request(url, data=body.getvalue(),
                                headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


# ===================== 轨道预设（按技能语义分配风格） =====================

KNIGHT_PRESETS: dict[str, list[dict]] = {
    "6001": [
        {"id": "slash_impact", "phase": "impact", "title": "普攻斩击命中",
         "description": "金属剑刃命中时的银白寒光迸溅", "trigger": "hit",
         "query": "sword slash impact metal spark", "color": "silver white", "tint": "#dfe8ff",
         "space": "character_local", "duration_ms": 300, "palette": ["#dfe8ff", "#9fb6d9"]},
    ],
    "6002": [
        {"id": "holy_release", "phase": "release", "title": "技能1 圣光起手",
         "description": "圣光金色剑光挥出的拖尾", "trigger": "release",
         "query": "holy light slash trail golden", "color": "golden", "tint": "#ffd76a",
         "space": "character_local", "duration_ms": 420, "palette": ["#ffd76a", "#fff3c4"]},
        {"id": "holy_impact", "phase": "impact", "title": "技能1 圣光命中",
         "description": "圣光爆发式命中闪光", "trigger": "hit",
         "query": "holy burst impact golden flash", "color": "golden", "tint": "#ffd76a",
         "space": "character_local", "duration_ms": 320, "palette": ["#ffd76a", "#fff3c4"]},
    ],
    "6003": [
        {"id": "area_burst", "phase": "area", "title": "技能2 范围爆发",
         "description": "金橙爆炸冲击波覆盖范围区域", "trigger": "hit",
         "query": "explosion shockwave area burst golden", "color": "golden orange", "tint": "#ffb347",
         "space": "world", "duration_ms": 700, "palette": ["#ffb347", "#ff7b3d"]},
    ],
    "6004": [
        {"id": "heavy_release", "phase": "release", "title": "技能3 重斩起手",
         "description": "重剑挥砍的大剑光弧线", "trigger": "release",
         "query": "heavy greatsword slash arc metal", "color": "silver white", "tint": "#dfe8ff",
         "space": "character_local", "duration_ms": 460, "palette": ["#dfe8ff", "#8fa4c8"]},
        {"id": "heavy_impact", "phase": "impact", "title": "技能3 重斩命中",
         "description": "重击爆裂的金属碎片迸溅", "trigger": "hit",
         "query": "heavy impact burst metal shards", "color": "silver white", "tint": "#dfe8ff",
         "space": "character_local", "duration_ms": 340, "palette": ["#dfe8ff", "#8fa4c8"]},
    ],
}


def generic_presets(nodes: list) -> list[dict]:
    """无预设时按节点类型推导（melee→impact，area/fullscreen→area，spawn_projectile→projectile）。"""
    presets: list[dict] = []
    seen: set[str] = set()
    for node in nodes:
        if not isinstance(node, dict):
            continue
        ntype = node.get("type")
        if ntype == "melee_damage" and "impact" not in seen:
            seen.add("impact")
            presets.append({"id": "impact", "phase": "impact", "title": "命中特效",
                            "description": "命中时的冲击光效", "trigger": "hit",
                            "query": "impact hit burst slash", "color": "", "tint": "#ffffff",
                            "space": "character_local", "duration_ms": 320, "palette": ["#ffffff"]})
        elif ntype in ("area_damage", "fullscreen_damage") and "area" not in seen:
            seen.add("area")
            presets.append({"id": "area", "phase": "area", "title": "范围特效",
                            "description": "范围爆发冲击波", "trigger": "hit",
                            "query": "explosion shockwave area burst", "color": "", "tint": "#ffffff",
                            "space": "world", "duration_ms": 700, "palette": ["#ffb347"]})
        elif ntype == "spawn_projectile" and "projectile" not in seen:
            seen.add("projectile")
            presets.append({"id": "projectile", "phase": "projectile", "title": "弹道特效",
                            "description": "弹道飞行光效", "trigger": "hit",
                            "query": "projectile flying energy trail", "color": "", "tint": "#ffffff",
                            "space": "world", "duration_ms": 500, "palette": ["#9fd8ff"]})
    if not presets:
        presets.append({"id": "action", "phase": "release", "title": "动作特效",
                        "description": "技能动作光效", "trigger": "release",
                        "query": "skill cast magic energy", "color": "", "tint": "#ffffff",
                        "space": "character_local", "duration_ms": 420, "palette": ["#ffffff"]})
    return presets


# ===================== ActionContext 适配（skill_fx 版无 body_center，字段必须为 float） =====================

def to_fx_action_context(ctx: dict) -> dict:
    frame_count = max(1, int(ctx.get("frame_count", 1)))
    events = [
        {"name": str(e.get("name", "")), "frame": int(e.get("frame", 0))}
        for e in ctx.get("events", [])
        if str(e.get("name", "")).strip() and 0 <= int(e.get("frame", 0)) < frame_count
    ]
    windows = []
    for w in ctx.get("hit_windows", []):
        start = int(w.get("start_frame", 0))
        end = max(start, int(w.get("end_frame", 0)))
        if end >= frame_count:
            continue
        windows.append({
            "start_frame": start, "end_frame": end,
            "forward": float(w.get("forward") or 0.0), "y": float(w.get("y") or 0.0),
            "width": float(w.get("width") or 0.0), "height": float(w.get("height") or 0.0),
        })
    return {
        "name": str(ctx.get("name", "action")),
        "frame_count": frame_count,
        "fps": float(ctx.get("fps") or 24.0),
        "frame_size": {"width": int(ctx["frame_size"]["width"]), "height": int(ctx["frame_size"]["height"])},
        "foot_center": {"x": float(ctx.get("foot_center", {}).get("x", 0.0)), "y": float(ctx.get("foot_center", {}).get("y", 0.0))},
        "events": events[:64], "hit_windows": windows[:32], "sockets": [],
    }


def build_trigger(preset: dict, ctx: dict) -> dict:
    """按实际动作数据校正触发：release 事件缺失→判定窗口→技能开始。"""
    has_release = any(str(e.get("name", "")) == "release" for e in ctx.get("events", []))
    has_window = bool(ctx.get("hit_windows"))
    kind = preset.get("trigger", "hit")
    if kind == "release" and has_release:
        return {"type": "action_event", "event": "release", "hit_window_index": 0, "node_index": 0, "offset_ms": 0}
    if has_window:
        return {"type": "hit_window_start", "event": "", "hit_window_index": 0, "node_index": 0, "offset_ms": 0}
    return {"type": "skill_start", "event": "", "hit_window_index": 0, "node_index": 0, "offset_ms": 0}


def build_track(preset: dict, ctx: dict) -> dict:
    query = str(preset.get("query", "skill effect"))
    return {
        "id": preset["id"], "phase": preset["phase"],
        "title": preset["title"], "description": preset["description"],
        "trigger": build_trigger(preset, ctx),
        "space": preset.get("space", "character_local"),
        "anchor": "origin", "direction": "facing", "mirror": False,
        "duration_ms": int(preset.get("duration_ms", 400)),
        "blend_mode": "add", "layer": 1, "loop": False,
        "transform": {"offset": {"x": 0.0, "y": 0.0}, "scale": 1.0,
                      "rotation_degrees": 0.0, "opacity": 1.0, "tint": preset.get("tint", "#ffffff")},
        "library_query": query,
        "generation_prompt": f"{query}, {STYLE}, transparent background, centered composition, no text",
        "is_projectile": False,
    }


def bundle_id_for(char_name: str, skill_id: str) -> str:
    raw = f"{char_name}-{skill_id}".lower()
    cleaned = "".join(ch if (ch.isalnum() or ch in "_-") else "-" for ch in raw)
    while cleaned and not (cleaned[0].isalnum()):
        cleaned = cleaned[1:]
    return cleaned or f"fx-{skill_id}"


# ===================== 搜库 / 渲染 / 抠底 =====================

def search_library(backend: str, track: dict, preset: dict, exclude_ids: list[str], relaxed: bool = False) -> tuple[list, bool]:
    """搜库。relaxed=True 时去掉 space 约束（world/character_local 冲突是硬冲突主因）。"""
    payload = {
        "query": track["library_query"], "description": track["description"],
        "phase": track["phase"], "style": STYLE,
        "color": preset.get("color", ""), "tint": preset.get("tint", ""),
        "space": None if relaxed else track["space"],
        "anchor": track["anchor"], "direction": track["direction"],
        "duration_ms": track["duration_ms"], "loop": False,
        "blend_mode": track["blend_mode"], "is_projectile": False,
        "limit": 12, "offset": 0, "exclude_ids": exclude_ids,
    }
    resp = http_json(f"{backend}/skill-fx/library/search", payload, timeout=180)
    data = resp.get("data", resp)
    return data.get("items") or [], bool(data.get("needs_generation", True))


def _is_ui_asset(item: dict) -> bool:
    """排除 UI 类素材（图标/眼睛/框线等）——它们不应出现在技能特效里。"""
    name = str(item.get("name", "")).lower()
    path = str(item.get("path", "")).lower()
    tags = [str(tag).lower() for tag in (item.get("tags") or [])]
    return name.startswith("ui_") or "ui" in tags or "/ui/" in path or "图标" in name


def pick_asset(items: list, chosen: set[str], min_frames: int = 1) -> tuple[dict | None, bool]:
    """选源：跳过已选素材，按质量递降逐轮筛选，最后才接受带硬冲突项。

    UI 类素材硬排除（技能特效永远不应选到图标/框线）；仅当排除后为空才回退到全量。
    轮次：① 非 UI + 帧数达标 + 无冲突 ② 非 UI + 无冲突 ③ 非 UI 最高分（带冲突，低置信）
    """
    candidates = [item for item in items if str(item.get("id")) not in chosen]
    non_ui = [item for item in candidates if not _is_ui_asset(item)]
    pool_all = non_ui or candidates
    for pool in (
        [item for item in pool_all if int(item.get("frame_count") or 1) >= min_frames],
        pool_all,
    ):
        for item in pool:
            if not item.get("conflicts"):
                return item, True
    return (pool_all[0], False) if pool_all else (None, False)


def render_sheet(backend: str, item: dict) -> bytes:
    """用库返回的 preview_url 渲染 PNG sheet（去掉 vite 代理的 /api 前缀）。"""
    preview = str(item.get("preview_url", ""))
    if not preview:
        raise ValueError("库素材缺少 preview_url")
    path = preview.removeprefix("/api")
    return http_bytes(f"{backend}{path}")


def sheet_needs_keying(sheet_bytes: bytes) -> bool:
    """四角不透明 → 需要抠底（黑底/纯色底素材）。"""
    from PIL import Image

    image = Image.open(io.BytesIO(sheet_bytes)).convert("RGBA")
    w, h = image.size
    for point in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if image.getpixel(point)[3] != 0:
            return True
    return False


def process_frames(backend: str, sheet_bytes: bytes, frame_count: int, frame_w: int, frame_h: int) -> bytes:
    """切帧 → /skill-fx/visual/process（transparent 抠底 + 补帧到 target）→ 新 sheet。"""
    from PIL import Image

    image = Image.open(io.BytesIO(sheet_bytes)).convert("RGBA")
    files: list[tuple[str, str, bytes]] = []
    for index in range(frame_count):
        box = (index * frame_w, 0, min((index + 1) * frame_w, image.width), frame_h)
        if box[2] <= box[0]:
            break
        frame = image.crop(box)
        buf = io.BytesIO()
        frame.save(buf, format="PNG")
        files.append(("frames", f"frame_{index:02d}.png", buf.getvalue()))
    if not files:
        return sheet_bytes
    return http_multipart_png(
        f"{backend}/skill-fx/visual/process",
        {"frame_width": str(frame_w), "frame_height": str(frame_h),
         "target_frame_count": str(max(len(files), TARGET_FRAMES)),
         "background_mode": "transparent"},
        files,
    )


def sheet_geometry(sheet_bytes: bytes, item: dict) -> tuple[int, int, int, float]:
    """从 sheet 实际尺寸反推 (frame_count, frame_w, frame_h, fps)，避免 manifest 与图集不一致。"""
    from PIL import Image

    image = Image.open(io.BytesIO(sheet_bytes))
    parsed = urllib.parse.parse_qs(urllib.parse.urlparse(str(item.get("preview_url", ""))).query)
    frame_count = int((parsed.get("frame_count") or [item.get("frame_count") or TARGET_FRAMES])[0])
    frame_count = max(1, min(120, frame_count))
    frame_w = max(1, image.width // frame_count)
    frame_h = max(1, image.height)
    fps = float(item.get("fps") or 12.0)
    return frame_count, frame_w, frame_h, max(1.0, min(120.0, fps))


# ===================== 生成兜底（best-effort） =====================

def discover_image_generation(backend: str) -> str | None:
    """从 openapi.json 发现可用的图像生成端点（path 含 generat 且请求体含 prompt 字段）。"""
    try:
        spec = http_json(f"{backend}/openapi.json", timeout=60)
    except Exception:  # noqa: BLE001
        return None
    for path, methods in (spec.get("paths") or {}).items():
        if "generat" not in path.lower():
            continue
        post = (methods or {}).get("post")
        if not post:
            continue
        try:
            schema_ref = post["requestBody"]["content"]["application/json"]["schema"]
            schema = spec["components"]["schemas"][schema_ref["$ref"].rsplit("/", 1)[-1]]
        except Exception:  # noqa: BLE001
            continue
        props = schema.get("properties") or {}
        if any("prompt" in key.lower() for key in props):
            return path
    return None


def generate_frames(backend: str, endpoint: str, prompt: str) -> list[bytes] | None:
    """best-effort 调用图像生成端点取关键帧；任何异常返回 None（该轨道留空报告）。"""
    try:
        resp = http_json(f"{backend}{endpoint}", {"prompt": prompt, "count": 4}, timeout=600)
    except Exception as exc:  # noqa: BLE001
        print(f"      [generate] 调用失败：{exc}")
        return None
    found: list[bytes] = []

    def walk(value) -> None:
        if isinstance(value, dict):
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
        elif isinstance(value, str) and len(value) > 512:
            if value.startswith("data:image"):
                found.append(base64.b64decode(value.split(",", 1)[1]))
            elif value.startswith(("http://", "https://")):
                try:
                    found.append(http_bytes(value, timeout=120))
                except Exception:  # noqa: BLE001
                    pass

    walk(resp)
    return found or None


# ===================== bundle 导出 =====================

def export_bundle(backend: str, bundle_id: str, skill_id: str, skill: dict, fx_ctx: dict,
                  proposal: dict, assets: list[dict]) -> list[dict]:
    payload = {
        "bundle_id": bundle_id, "skill_id": str(skill_id),
        "skill_hash": sha16(skill), "action_hash": sha16(fx_ctx),
        "proposal": proposal, "assets": assets,
    }
    resp = http_json(f"{backend}/skill-fx/bundle/export", payload, timeout=180)
    return resp.get("data", resp).get("files") or []


def backup_bundle(bundle_dir: Path) -> Path | None:
    if not bundle_dir.is_dir():
        return None
    target = BACKUP_ROOT / datetime.now().strftime("%Y%m%d_%H%M%S") / bundle_dir.name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(bundle_dir, target, dirs_exist_ok=True)
    return target


def sync_web_state(skill_id: str, track_ids: set[str]) -> str:
    """同步网页编排台的 AI 特效 checkpoint。

    前端 `loadAndHydrateDirectorState` 的优先级是：checkpoint > bundle（仅当 checkpoint
    缺失/缺 phase·trigger/完全为空时才从 bundle 重建）。所以若已存在一份不含本次轨道的
    旧 checkpoint，网页就看不到本次配置——备份后移除，让它从 bundle 自动重建。
    """
    state_dir = WEB_STATE_ROOT / str(skill_id)
    if not state_dir.is_dir():
        return "无 checkpoint（网页首次打开会从 bundle 自动生成）"
    for state_file in state_dir.glob("*.json"):
        try:
            data = json.loads(state_file.read_text(encoding="utf-8-sig"))
        except Exception:  # noqa: BLE001
            continue
        existing = {
            str(track.get("id"))
            for proposal in (data.get("proposals") or [])
            for track in (proposal.get("tracks") or [])
            if isinstance(track, dict)
        }
        if track_ids and track_ids <= existing:
            return "checkpoint 已包含本次轨道，保留"
    target = WEB_STATE_BACKUP_ROOT / datetime.now().strftime("%Y%m%d_%H%M%S") / str(skill_id)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(state_dir, target, dirs_exist_ok=True)
    shutil.rmtree(state_dir)
    return f"旧 checkpoint 已备份并移除 → {target.relative_to(PROJECT)}"


# ===================== 主流程 =====================

def main() -> int:
    parser = argparse.ArgumentParser(description="headless 技能特效自动配置（只产 bundle）")
    parser.add_argument("--actors", default="7001", help="角色 ID 列表，逗号分隔")
    parser.add_argument("--backend", default="http://localhost:8000", help="后端地址")
    parser.add_argument("--dry-run", action="store_true", help="只搜库出报告，不写盘")
    parser.add_argument("--keep-web-state", action="store_true",
                        help="保留已有的网页 AI 特效 checkpoint（默认：不含本次轨道的旧 checkpoint 会备份后移除，以便网页从 bundle 重建）")
    args = parser.parse_args()

    try:
        info = http_json(f"{args.backend}/skill-fx/library/index?refresh=false", payload={}, timeout=120)
        lib = info.get("data", info)
        print(f"[fx] 特效库索引：{lib.get('count', '?')} 个素材，来源 {lib.get('sources', {})}")
    except Exception as exc:  # noqa: BLE001
        print(f"[fx] 后端不可用（{args.backend}）：{exc}", file=sys.stderr)
        print("请先启动后端：python -m uvicorn backend.app.main:app --port 8000", file=sys.stderr)
        return 2

    gen_endpoint = None if args.dry_run else discover_image_generation(args.backend)
    print(f"[fx] 图像生成兜底端点：{gen_endpoint or '未发现（匹配不到的轨道将留空报告）'}")

    characters = load_json(DATA / "characters.json")
    report: list[str] = []
    produced: list[str] = []

    for actor_id in [a.strip() for a in args.actors.split(",") if a.strip()]:
        char = characters.get(actor_id)
        if not char:
            print(f"[{actor_id}] characters.json 无此角色，跳过")
            continue
        char_name = str(char.get("name") or actor_id)
        slug = str(char.get("asset", "")).removeprefix("res://assets/characters/")
        actor_path = ACTORS_DIR / f"{actor_id}.json"
        if not actor_path.is_file():
            print(f"[{actor_id}] 缺少 {actor_path.name}，跳过")
            continue
        actor_skills = load_json(actor_path)
        print(f"\n===== {actor_id} {char_name}（{slug}）：{len(actor_skills)} 个技能 =====")
        chosen_ids: set[str] = set()   # 跨技能去重：同一素材不重复用（代替轮换）

        for skill_index, (skill_id, skill) in enumerate(actor_skills.items()):
            nodes = skill.get("nodes", [])
            action_name = next((n.get("action") for n in nodes if n.get("type") == "play_animation"), "")
            raw_ctx = build_action_context(slug, str(action_name)) if action_name else None
            if not raw_ctx:
                print(f"  --- 技能 {skill_id}：缺少动作上下文（action={action_name}），跳过")
                continue
            fx_ctx = to_fx_action_context(raw_ctx)
            bundle_id = bundle_id_for(char_name, str(skill_id))
            presets = KNIGHT_PRESETS.get(str(skill_id)) or generic_presets(nodes)
            tracks = [build_track(preset, fx_ctx) for preset in presets]
            palette: list[str] = []
            for preset in presets:
                for color in preset.get("palette", []):
                    if color not in palette:
                        palette.append(color)
            proposal = {
                "id": f"{bundle_id}-unified",
                "title": f"{skill.get('name', skill_id)} 特效方案",
                "summary": "headless 库匹配自动配置：按技能语义选风格，素材来自本地特效库",
                "style": STYLE,
                "palette": (palette or ["#ffffff"])[:6],
                "tracks": tracks,
            }
            print(f"  --- 技能 {skill_id} {skill.get('name', '')}（动作 {action_name}，bundle {bundle_id}）---")

            assets: list[dict] = []
            staged: list[tuple[Path, bytes]] = []
            for track_index, (preset, track) in enumerate(zip(presets, tracks)):
                role = track["id"]
                exclude = sorted(chosen_ids)
                needs_gen = True
                items: list = []
                item: dict | None = None
                clean = False
                try:
                    min_frames = 4 if int(track["duration_ms"]) >= 400 else 1
                    items, needs_gen = search_library(args.backend, track, preset, exclude)
                    item, clean = pick_asset(items, chosen_ids, min_frames)
                    if item is not None and not clean:
                        # 硬冲突（多为 space/phase 画像排斥）→ 放宽 space 重搜一次
                        relaxed_items, _ = search_library(args.backend, track, preset, exclude, relaxed=True)
                        relaxed_item, relaxed_clean = pick_asset(relaxed_items, chosen_ids, min_frames)
                        if relaxed_item is not None and relaxed_clean:
                            items, item, clean = relaxed_items, relaxed_item, True
                except Exception as exc:  # noqa: BLE001
                    print(f"    [搜库失败] {role}：{exc}")
                    items, item, clean, needs_gen = [], None, False, True

                score = float((item or {}).get("score", 0) or 0.0)
                conflicts = (item or {}).get("conflicts") or []
                if item is None:
                    source_text = "无库命中"
                elif clean and score >= 0.52:
                    source_text = f"library score={score:.3f} {item.get('name', '')}"
                else:
                    source_text = f"library(低置信) score={score:.3f} {item.get('name', '')} 冲突={conflicts}"
                if item is not None:
                    chosen_ids.add(str(item.get("id")))

                if args.dry_run:
                    best = float(items[0].get("score", 0)) if items else 0.0
                    print(f"    [dry] {role}: best={best:.3f} needs_gen={needs_gen} → {source_text}")
                    report.append(f"{actor_id}/{skill_id} {role}: best={best:.3f} needs_gen={needs_gen} → {source_text}")
                    continue

                sheet_bytes: bytes | None = None
                if item is not None:
                    try:
                        sheet_bytes = render_sheet(args.backend, item)
                    except Exception as exc:  # noqa: BLE001
                        print(f"    [渲染失败] {role}：{exc}")
                        sheet_bytes = None
                if sheet_bytes is None and gen_endpoint:
                    frames = generate_frames(args.backend, gen_endpoint, track["generation_prompt"])
                    if frames:
                        try:
                            sheet_bytes = process_frames(args.backend, frames[0], len(frames), TARGET_FRAME_SIZE, TARGET_FRAME_SIZE)
                            source_text = f"generated({len(frames)} 帧)"
                        except Exception as exc:  # noqa: BLE001
                            print(f"    [生成合成失败] {role}：{exc}")
                if sheet_bytes is None:
                    print(f"    [留空] {role}：{source_text}，需在网页特效导演里单独生成")
                    report.append(f"{actor_id}/{skill_id} {role}: 留空（{source_text}，需网页生成）")
                    continue

                frame_count, frame_w, frame_h, fps = sheet_geometry(sheet_bytes, item or {})
                if item is not None and (str(item.get("source_type")) != "sequence" or sheet_needs_keying(sheet_bytes)):
                    try:
                        keyed = process_frames(args.backend, sheet_bytes, frame_count, frame_w, frame_h)
                        sheet_bytes = keyed
                        frame_count, frame_w, frame_h, fps = sheet_geometry(sheet_bytes, item)
                    except Exception as exc:  # noqa: BLE001
                        print(f"    [抠底失败，沿用原图] {role}：{exc}")

                atlas_rel = f"{SKILL_FX_RES_ROOT}/{bundle_id}/visual/{role}/atlas.png"
                staged.append((SKILL_FX_ROOT / bundle_id / "visual" / role / "atlas.png", sheet_bytes))
                scale = normalize_track_scale(track, frame_w, frame_h)
                assets.append({
                    "track_id": role,
                    "atlas_path": atlas_rel,
                    "scene_path": f"{SKILL_FX_RES_ROOT}/{bundle_id}/godot/effect_scenes/{role}/effect.tscn",
                    "frame_size": {"width": frame_w, "height": frame_h},
                    "frame_count": frame_count, "fps": round(fps, 3), "loop": bool(track["loop"]),
                    "source": {"library_id": (item or {}).get("id"), "name": (item or {}).get("name"),
                               "score": (item or {}).get("score"), "source_type": (item or {}).get("source_type")},
                })
                print(f"    [选中] {role} ← {source_text} | {frame_count} 帧 {frame_w}x{frame_h} @{fps:.1f}fps scale={scale}")
                report.append(f"{actor_id}/{skill_id} {role}: {source_text} | {frame_count}帧 {frame_w}x{frame_h} @{fps:.1f}fps scale={scale}")

            if args.dry_run or not assets:
                continue

            # 写图集（先备份存量 bundle）
            backup = backup_bundle(SKILL_FX_ROOT / bundle_id)
            if backup:
                print(f"    [备份] 旧 bundle → {backup.relative_to(PROJECT)}")
            for path, content in staged:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)

            try:
                files = export_bundle(args.backend, bundle_id, str(skill_id), skill, fx_ctx, proposal, assets)
            except urllib.error.HTTPError as exc:  # noqa: PERF203
                detail = exc.read().decode("utf-8", "replace")[:400]
                print(f"    [导出失败] {bundle_id}：HTTP {exc.code} {detail}")
                report.append(f"{actor_id}/{skill_id} {bundle_id}: 导出失败 HTTP {exc.code}")
                continue
            for entry in files:
                target = PROJECT / str(entry["path"]).replace("\\", "/")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(str(entry.get("text", "")), encoding="utf-8")
            produced.append(bundle_id)
            state_note = sync_web_state(str(skill_id), {asset["track_id"] for asset in assets}) if not args.keep_web_state \
                else "保留旧 checkpoint（--keep-web-state）"
            print(f"    [导出] {bundle_id}：{len(files)} 个文件（{len(assets)} 轨道）")
            print(f"    [网页状态] {state_note}")

    print("\n===== 汇总 =====")
    for line in report:
        print(f"  {line}")
    if args.dry_run:
        print("（dry-run：未写盘）")
        return 0
    if produced:
        print(f"\n产出 bundle：{', '.join(produced)}")
        print("下一步：在 Godot「技能节点配置」里选中对应技能，点『导入 AI 特效包』写入 play_effect 节点。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
