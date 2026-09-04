#!/usr/bin/env python3
"""headless 技能音效自动配置（库匹配优先 + Stable Audio 生成兜底）。

复用网页侧音效管线的全部契约，一次性给指定角色的全部技能配好音效：
  1. 轨道策划：POST /api/audio/plan（LLM，失败退化为确定性拆轨）
  2. 音源选择：POST /api/audio/library/search（CLAP 库匹配，needs_generation=False 直接用）
     否则 POST /api/audio/generate（Stable Audio，按 clap_score 选最优）
  3. 导出 bundle：assets/skill_audio/<bundle_id>/（wav + manifest.json，格式 frame-ronin-skill-audio-v1）
  4. 幂等写入：data/skills/actors/<actor>.json 插入 play_sound 节点 / 弹道·命中音效字段
     （严格复刻 frontend/src/lib/skillAudioApply.ts 的 resolveAudioTrigger + buildPlaySoundNode）

用法：
  python tools/configure_skill_audio.py --dry-run          # 只看拆轨与匹配报告，不写盘
  python tools/configure_skill_audio.py                     # 实跑骑士 7001 + 法师 7003
  python tools/configure_skill_audio.py --actors 7003 --threshold 0.5
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import shutil
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent          # hengban-2/
DATA = PROJECT / "data"
ACTORS_DIR = DATA / "skills" / "actors"
BUNDLE_ROOT = PROJECT / "assets" / "skill_audio"
BACKUP_ROOT = PROJECT / ".frame-ronin" / "backups" / "skill_audio"

ISOLATION = "no music, no voice, isolated sound effect"


# ===================== 基础工具 =====================

def http_json(url: str, payload: dict | None = None, timeout: int = 180) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_bytes(url: str, timeout: int = 60) -> bytes:
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return resp.read()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha16(value) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()[:16]


def bundle_id_for_skill(skill_id: str) -> str:
    return "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in skill_id.lower())


# ===================== 动作上下文（对齐后端 ActionContext） =====================

def build_action_context(slug: str, action_name: str) -> dict | None:
    manifest_path = PROJECT / "assets" / "characters" / slug / "manifest.json"
    combat_path = PROJECT / "assets" / "characters" / slug / "combat_actions.json"
    if not manifest_path.is_file() or not combat_path.is_file():
        return None
    manifest = load_json(manifest_path)
    combat = load_json(combat_path)
    entry = next((a for a in manifest.get("actions", []) if a.get("actionName") == action_name), None)
    if entry is None:
        return None
    runtime = entry.get("runtimeAction", {})
    combat_action = combat.get("actions", {}).get(action_name, {})
    frame_size = manifest.get("frameSize", {"width": 256, "height": 256})
    foot = runtime.get("foot_center", {"x": 0, "y": 0})
    return {
        "name": action_name,
        "frame_count": max(1, int(entry.get("frameCount", 1))),
        "fps": float(entry.get("fps") or 24),
        "frame_size": {"width": int(frame_size.get("width", 256)), "height": int(frame_size.get("height", 256))},
        "foot_center": {"x": float(foot.get("x", 0)), "y": float(foot.get("y", 0))},
        "body_center": {"x": float(foot.get("x", 0)), "y": float(foot.get("y", 0))},
        "events": [{"name": str(e.get("name", "")), "frame": int(e.get("frame", 0))} for e in combat_action.get("events", [])],
        "hit_windows": [
            {
                "start_frame": int(w.get("start_frame", 0)),
                "end_frame": int(w.get("end_frame", 0)),
                "forward": w.get("forward"),
                "y": w.get("y"),
                "width": w.get("width"),
                "height": w.get("height"),
            }
            for w in combat_action.get("hit_windows", [])
        ],
        "sockets": [],
    }


# ===================== 确定性拆轨（LLM 不可用时的兜底，规则同 audio_director） =====================

def role_prompt(role: str, damage_type: str, hint: str = "") -> str:
    magic = damage_type in ("magic", "fire", "ice", "lightning", "arcane")
    templates = {
        "action": f"fantasy {damage_type} skill full action sound, whoosh with impact{hint}, {ISOLATION}",
        "projectile_spawn": ("magic projectile launch whoosh, arcane energy release" if magic else "arrow release whoosh, bowstring snap") + f"{hint}, {ISOLATION}",
        "projectile_hit": f"projectile impact hit, sharp puncture thud{hint}, {ISOLATION}",
        "melee_hit": f"melee {damage_type} hit, sharp impact crunch{hint}, {ISOLATION}",
        "area_hit": f"area explosion impact, deep boom with debris{hint}, {ISOLATION}",
    }
    return templates.get(role, f"game sound effect {role}{hint}, {ISOLATION}")


def make_track(track_id: str, role: str, trigger: dict, prompt_en: str, duration_ms: int,
               bound_node_type: str = "play_sound", bound_node_index: int = -1,
               spatial_mode: str = "caster", loop: bool = False) -> dict:
    return {
        "id": track_id, "role": role, "trigger": trigger,
        "summary_zh": role, "prompt_en": prompt_en,
        "duration_ms": max(200, min(8000, int(duration_ms))),
        "spatial_mode": spatial_mode, "gain_db": -3.0, "pitch_variation": 0.05,
        "loop": loop, "candidate_count": 1, "omit": False,
        "bound_node_type": bound_node_type, "bound_node_index": bound_node_index,
    }


def derive_tracks(skill: dict, nodes: list, action_ctx: dict | None) -> list[dict]:
    damage_type = str(skill.get("damage_type") or next(
        (n.get("damage_tag") for n in nodes if isinstance(n, dict) and n.get("damage_tag")), "slash"))
    action_ms = 800
    if action_ctx:
        action_ms = int(action_ctx["frame_count"] / max(1.0, action_ctx["fps"]) * 1000)
    tracks: list[dict] = [make_track("action", "action", {"type": "skill_start", "offset_ms": 0},
                                     role_prompt("action", damage_type), action_ms)]
    for index, node in enumerate(nodes):
        if not isinstance(node, dict):
            continue
        ntype = node.get("type")
        if ntype == "spawn_projectile":
            hint = ""
            if node.get("emission") == "sequence":
                count = int(node.get("count") or 1)
                interval = float(node.get("interval") or 0.15)
                hint = f", {count} quick shots in succession"
                duration = int(max(count - 1, 0) * interval * 1000) + 600
            else:
                duration = 500
            tracks.append(make_track("projectile_spawn", "projectile_spawn",
                                     {"type": "after_skill_node", "node_index": index, "offset_ms": 0},
                                     role_prompt("projectile_spawn", damage_type, hint), duration,
                                     bound_node_type="spawn_projectile", bound_node_index=index))
            tracks.append(make_track("projectile_hit", "projectile_hit",
                                     {"type": "hit_window_start", "hit_window_index": 0, "offset_ms": 0},
                                     role_prompt("projectile_hit", damage_type), 400,
                                     bound_node_type="spawn_projectile", bound_node_index=index,
                                     spatial_mode="target"))
        elif ntype == "melee_damage":
            tracks.append(make_track("melee_hit", "melee_hit",
                                     {"type": "hit_window_start", "hit_window_index": int(node.get("hit_window_index") or 0), "offset_ms": 0},
                                     role_prompt("melee_hit", damage_type), 400,
                                     bound_node_type="melee_damage", bound_node_index=index,
                                     spatial_mode="target"))
        elif ntype in ("area_damage", "fullscreen_damage"):
            tracks.append(make_track("area_hit", "area_hit",
                                     {"type": "hit_window_start", "hit_window_index": int(node.get("hit_window_index") or 0), "offset_ms": 0},
                                     role_prompt("area_hit", damage_type), 700,
                                     bound_node_type=ntype, bound_node_index=index,
                                     spatial_mode="fullscreen" if ntype == "fullscreen_damage" else "target"))
    # 去重（同 role 只保留首条）
    seen: set[str] = set()
    unique: list[dict] = []
    for track in tracks:
        if track["role"] in seen:
            continue
        seen.add(track["role"])
        unique.append(track)
    return unique


# ===================== 后端管线调用 =====================

def plan_via_backend(backend: str, skill_id: str, skill: dict, nodes: list, action_ctx: dict | None) -> list[dict] | None:
    if action_ctx is None:
        return None
    damage_type = str(skill.get("damage_type") or next(
        (n.get("damage_tag") for n in nodes if isinstance(n, dict) and n.get("damage_tag")), "slash"))
    payload = {
        "skill_id": skill_id,
        "skill_name": str(skill.get("name", skill_id)),
        "description": str(skill.get("description", "")),
        "damage_type": damage_type,
        "skill_nodes": nodes,
        "action": action_ctx,
        "fx_storyboard_data_url": "",
        "existing_track_ids": [],
        "plan_mode": "auto",
        "llm_provider": "local",
        "llm_model": "qwen3:8b",
    }
    try:
        resp = http_json(f"{backend}/audio/plan", payload, timeout=300)
        tracks = resp.get("data", {}).get("tracks") or resp.get("tracks") or []
        tracks = [t for t in tracks if isinstance(t, dict) and not t.get("omit")]
        return tracks or None
    except Exception as exc:  # noqa: BLE001
        print(f"    [plan] LLM 策划失败，退化为确定性拆轨：{exc}")
        return None


def match_library(backend: str, track: dict, threshold: float | None, rotation: int = 0) -> tuple[bytes, dict] | None:
    payload = {
        "role": track.get("role", "action"),
        "prompt_en": track.get("prompt_en", ""),
        "summary_zh": track.get("summary_zh", ""),
        "duration_ms": int(track.get("duration_ms", 800)),
        "spatial_mode": track.get("spatial_mode", "caster"),
        "loop": bool(track.get("loop", False)),
        "limit": 5, "offset": 0,
    }
    if threshold is not None:
        payload["threshold"] = threshold
    try:
        resp = http_json(f"{backend}/audio/library/search", payload, timeout=120)
    except Exception as exc:  # noqa: BLE001
        print(f"    [library] 搜索失败：{exc}")
        return None
    data = resp.get("data", resp)
    items = data.get("items") or []
    if not items or data.get("needs_generation", True):
        best = items[0]["score"] if items else 0.0
        print(f"    [library] 最高分 {best:.3f} 低于阈值，转生成")
        return None
    # Top-N 轮换：同类轨道在不同技能间轮换候选，避免 8 个技能共用同一条音效的听感重复
    best_item = items[rotation % len(items)]
    try:
        audio_bytes = http_bytes(f"{backend}/audio/library/file?id={best_item['id']}")
    except Exception as exc:  # noqa: BLE001
        print(f"    [library] 取文件失败：{exc}")
        return None
    return audio_bytes, {
        "source": "library", "id": best_item["id"], "name": best_item.get("name", ""),
        "score": best_item.get("score", 0.0), "ext": best_item.get("ext", "wav"),
        "duration_ms": best_item.get("duration_ms", int(track.get("duration_ms", 800))),
    }


def generate_audio(backend: str, track: dict) -> tuple[bytes, dict] | None:
    payload = {
        "prompt_en": track.get("prompt_en", ""),
        "duration_ms": int(track.get("duration_ms", 800)),
        "candidate_count": 3,
    }
    try:
        resp = http_json(f"{backend}/audio/generate", payload, timeout=600)
    except Exception as exc:  # noqa: BLE001
        print(f"    [generate] 失败：{exc}")
        return None
    candidates = resp.get("data", {}).get("candidates") or []
    if not candidates:
        return None
    best = candidates[0]  # 后端已按 clap_score 降序
    try:
        audio_bytes = base64.b64decode(best["audio_data_url"].split(",", 1)[1])
    except Exception as exc:  # noqa: BLE001
        print(f"    [generate] 解码失败：{exc}")
        return None
    return audio_bytes, {
        "source": "generated", "seed": best.get("seed"), "clap_score": best.get("clap_score"),
        "model": best.get("model", ""), "ext": "wav",
        "duration_ms": best.get("duration_ms", int(track.get("duration_ms", 800))),
    }


# ===================== 应用 play_sound（复刻 skillAudioApply.ts） =====================

def wait_node_frame(node: dict, action_ctx: dict | None) -> int | None:
    ntype = node.get("type")
    if ntype == "wait_action_frame":
        return int(node.get("frame", 0))
    if ntype == "wait_action_event" and action_ctx:
        event = next((e for e in action_ctx.get("events", []) if str(e.get("name")) == str(node.get("event", ""))), None)
        return int(event["frame"]) if event else None
    if ntype == "wait_hit_window" and action_ctx:
        windows = action_ctx.get("hit_windows", [])
        idx = int(node.get("hit_window_index", 0))
        return int(windows[idx]["start_frame"]) if 0 <= idx < len(windows) else None
    return None


def find_equivalent_wait_node(nodes: list, play_index: int, action_ctx: dict | None, target_frame: int) -> int:
    for index in range(play_index + 1, len(nodes)):
        if nodes[index].get("type") == "play_animation":
            break
        frame = wait_node_frame(nodes[index], action_ctx)
        if frame is not None and frame == target_frame:
            return index
    return -1


def find_wait_node(nodes: list, ntype: str, field: str, expected) -> int:
    for index, node in enumerate(nodes):
        if node.get("type") == ntype and node.get(field) == expected:
            return index
    return -1


def resolve_audio_trigger(track: dict, nodes: list, play_index: int, action_ctx: dict | None, fps: float) -> tuple[int, int, str]:
    trigger = track.get("trigger") or {}
    trigger_type = str(trigger.get("type", "skill_start"))
    base_index = play_index
    delay = max(0, int(trigger.get("offset_ms") or 0))
    warning = ""
    if trigger_type == "action_event":
        event = str(trigger.get("value", ""))
        wait_index = find_wait_node(nodes, "wait_action_event", "event", event)
        if wait_index >= 0:
            base_index = wait_index
        else:
            event_data = next((e for e in (action_ctx or {}).get("events", []) if str(e.get("name")) == event), None) if action_ctx else None
            event_frame = int(event_data["frame"]) if event_data else None
            equivalent = find_equivalent_wait_node(nodes, play_index, action_ctx, event_frame) if event_frame is not None else -1
            if equivalent >= 0:
                base_index = equivalent
            elif event_frame is not None:
                delay += int(event_frame / max(1.0, fps) * 1000)
            else:
                warning = f"未找到事件 {event} 的 wait_action_event，已回退到技能开始"
    elif trigger_type == "hit_window_start":
        window_index = int(trigger.get("hit_window_index", 0))
        wait_index = find_wait_node(nodes, "wait_hit_window", "hit_window_index", window_index)
        if wait_index >= 0:
            base_index = wait_index
        else:
            windows = (action_ctx or {}).get("hit_windows", []) if action_ctx else []
            window_frame = int(windows[window_index]["start_frame"]) if 0 <= window_index < len(windows) else None
            equivalent = find_equivalent_wait_node(nodes, play_index, action_ctx, window_frame) if window_frame is not None else -1
            if equivalent >= 0:
                base_index = equivalent
            elif window_frame is not None:
                delay += int(window_frame / max(1.0, fps) * 1000)
            else:
                warning = f"未找到判定框 {window_index} 的 wait_hit_window，已回退到技能开始"
    elif trigger_type == "after_skill_node":
        base_index = max(0, min(len(nodes) - 1, int(trigger.get("node_index", 0))))
    return base_index, delay, warning


def build_play_sound_node(track: dict, audio_path: str, delay_ms: int) -> dict:
    return {
        "type": "play_sound",
        "audio_path": audio_path,
        "spatial_mode": str(track.get("spatial_mode", "caster")),
        "gain_db": float(track.get("gain_db", 0) or 0),
        "pitch_variation": float(track.get("pitch_variation", 0) or 0),
        "loop": bool(track.get("loop", False)),
        "delay_ms": max(0, int(delay_ms)),
        "stop_on_skill_end": bool(track.get("loop", False)),
        "bus": "SFX",
        "source_track_id": str(track.get("id", "")),
    }


def apply_tracks(skill_nodes: list, tracks: list, selections: dict, bundle_id: str,
                 action_ctx: dict | None, fps: float) -> tuple[list, list[str]]:
    """返回 (新 nodes, warnings)。selections: track_id -> 选中文件名。"""
    warnings: list[str] = []
    track_ids = {t["id"] for t in tracks}
    nodes = [n for n in skill_nodes if not (
        n.get("type") == "play_sound" and str(n.get("source_track_id", "")) in track_ids
    )]
    play_index = next((i for i, n in enumerate(nodes) if n.get("type") == "play_animation"), -1)
    if play_index < 0:
        return skill_nodes, ["技能缺少 play_animation 节点，无法插入音效"]

    descriptors: list[tuple[int, dict]] = []
    for track in tracks:
        file_name = selections.get(track["id"])
        if not file_name:
            continue
        audio_path = f"res://assets/skill_audio/{bundle_id}/{file_name}"
        bound_type = str(track.get("bound_node_type", "play_sound"))
        bound_index = int(track.get("bound_node_index", -1))
        if bound_type == "play_sound":
            base_index, delay, warning = resolve_audio_trigger(track, nodes, play_index, action_ctx, fps)
            if warning:
                warnings.append(f"轨道 {track['id']}：{warning}")
            descriptors.append((base_index, build_play_sound_node(track, audio_path, delay)))
        elif bound_type == "spawn_projectile":
            if not (0 <= bound_index < len(nodes)) or nodes[bound_index].get("type") != "spawn_projectile":
                warnings.append(f"轨道 {track['id']}：spawn_projectile 索引 {bound_index} 无效，已跳过")
                continue
            cfg = {"audio_path": audio_path, "gain_db": float(track.get("gain_db", 0) or 0),
                   "pitch_variation": float(track.get("pitch_variation", 0) or 0),
                   "source_track_id": str(track["id"])}
            role = str(track.get("role", ""))
            if role == "projectile_flight":
                cfg["loop"] = True
            field = {"projectile_spawn": "spawn_audio", "projectile_flight": "flight_audio"}.get(role, "hit_audio")
            nodes[bound_index][field] = cfg
        elif bound_type in ("melee_damage", "area_damage", "fullscreen_damage"):
            if not (0 <= bound_index < len(nodes)) or nodes[bound_index].get("type") != bound_type:
                warnings.append(f"轨道 {track['id']}：{bound_type} 索引 {bound_index} 无效，已跳过")
                continue
            spatial = str(track.get("spatial_mode", "caster"))
            nodes[bound_index]["on_hit_audio"] = {
                "audio_path": audio_path, "gain_db": float(track.get("gain_db", 0) or 0),
                "pitch_variation": float(track.get("pitch_variation", 0) or 0),
                "spatial_mode": "target" if spatial == "caster" else spatial,
                "source_track_id": str(track["id"]),
            }
    descriptors.sort(key=lambda item: item[0], reverse=True)
    for base_index, node in descriptors:
        nodes.insert(base_index + 1, node)
    return nodes, warnings


# ===================== 主流程 =====================

def main() -> int:
    parser = argparse.ArgumentParser(description="headless 技能音效自动配置")
    parser.add_argument("--actors", default="7001,7003", help="角色 ID 列表，逗号分隔")
    parser.add_argument("--backend", default="http://localhost:8000", help="后端地址")
    parser.add_argument("--threshold", type=float, default=None, help="库匹配分阈值（缺省用后端按 role 的阈值）")
    parser.add_argument("--dry-run", action="store_true", help="只出报告，不写盘")
    args = parser.parse_args()

    # 后端探活
    try:
        status = http_json(f"{args.backend}/audio/library/status", timeout=30)
        lib = status.get("data", status)
        print(f"[audio] 音效库：{lib.get('total', '?')} 素材，已打标 {lib.get('labeled', '?')}")
    except Exception as exc:  # noqa: BLE001
        print(f"[audio] 后端不可用（{args.backend}）：{exc}", file=sys.stderr)
        print("请先启动后端：uvicorn backend.app.main:app --port 8000", file=sys.stderr)
        return 2

    characters = load_json(DATA / "characters.json")
    actor_ids = [a.strip() for a in args.actors.split(",") if a.strip()]
    report: list[str] = []
    total_tracks = 0
    library_hits = 0

    for actor_id in actor_ids:
        char = characters.get(actor_id)
        if not char:
            print(f"[{actor_id}] characters.json 无此角色，跳过")
            continue
        slug = str(char.get("asset", "")).removeprefix("res://assets/characters/")
        actor_path = ACTORS_DIR / f"{actor_id}.json"
        if not actor_path.is_file():
            print(f"[{actor_id}] 缺少 {actor_path.name}，跳过")
            continue
        actor_skills = load_json(actor_path)
        print(f"\n===== {actor_id} {char.get('name', '')}（{slug}）：{len(actor_skills)} 个技能 =====")
        changed = False

        for skill_index, (skill_id, skill) in enumerate(actor_skills.items()):
            nodes = skill.get("nodes", [])
            action_name = next((n.get("action") for n in nodes if n.get("type") == "play_animation"), "")
            action_ctx = build_action_context(slug, str(action_name)) if action_name else None
            fps = float((action_ctx or {}).get("fps", 24))
            print(f"  --- 技能 {skill_id} {skill.get('name', '')}（动作 {action_name}）---")

            tracks = plan_via_backend(args.backend, str(skill_id), skill, nodes, action_ctx)
            source = "LLM"
            if not tracks:
                tracks = derive_tracks(skill, nodes, action_ctx)
                source = "确定性拆轨"
            print(f"    拆轨（{source}）：{[t.get('role') for t in tracks]}")

            selections: dict[str, str] = {}
            manifest_tracks: list[dict] = []
            bundle_id = bundle_id_for_skill(str(skill_id))
            bundle_dir = BUNDLE_ROOT / bundle_id
            audio_files: dict[str, tuple[str, bytes]] = {}

            for track_index, track in enumerate(tracks):
                role = track.get("role", "action")
                # 轮换种子：技能序号 + 轨道序号，保证同角色不同技能的同类轨道选到不同候选
                rotation = skill_index + track_index
                picked = match_library(args.backend, track, args.threshold, rotation)
                if picked is None:
                    picked = generate_audio(args.backend, track)
                if picked is None:
                    print(f"    [跳过] {role}：库匹配与生成均失败")
                    manifest_tracks.append({**track, "candidates": [], "selected_candidate_index": -1})
                    continue
                audio_bytes, meta = picked
                ext = str(meta.get("ext", "wav")).lstrip(".")
                file_name = f"{track['id']}_{track_index + 1:02d}_v1.{ext}"
                audio_files[track["id"]] = (file_name, audio_bytes)
                selections[track["id"]] = file_name
                total_tracks += 1
                if meta.get("source") == "library":
                    library_hits += 1
                score_text = (f"score={meta['score']:.3f}" if meta.get("source") == "library"
                              else f"clap={meta.get('clap_score')}")
                source_name = meta.get("name") or meta.get("model") or ""
                print(f"    [选中] {role} ← {meta['source']} {score_text} {source_name} → {file_name}")
                manifest_tracks.append({
                    **track,
                    "candidates": [{
                        "index": 0, "file": file_name,
                        "seed": meta.get("seed"), "model": meta.get("model", "library" if meta.get("source") == "library" else ""),
                        "library_id": meta.get("id"), "library_score": meta.get("score"),
                        "clap_score": meta.get("clap_score"),
                        "prompt_en": track.get("prompt_en", ""),
                        "duration_ms": meta.get("duration_ms", track.get("duration_ms")),
                        "created_at": datetime.now().astimezone().isoformat(timespec="seconds"),
                    }],
                    "selected_candidate_index": 0,
                })
                report.append(f"{actor_id}/{skill_id} {role}: {meta['source']} {score_text} {source_name} → {bundle_id}/{file_name}")

            if args.dry_run or not selections:
                continue

            # 导出 bundle（wav + manifest）
            bundle_dir.mkdir(parents=True, exist_ok=True)
            for track_id, (file_name, audio_bytes) in audio_files.items():
                (bundle_dir / file_name).write_bytes(audio_bytes)
            manifest = {
                "format": "frame-ronin-skill-audio-v1", "version": 1,
                "skill_id": str(skill_id),
                "skill_hash": sha16(skill),
                "action_hash": sha16(action_ctx or {}),
                "tracks": manifest_tracks,
            }
            save_json(bundle_dir / "manifest.json", manifest)

            # 幂等写入技能节点
            new_nodes, warnings = apply_tracks(nodes, tracks, selections, bundle_id, action_ctx, fps)
            for warning in warnings:
                print(f"    [警告] {warning}")
            skill["nodes"] = new_nodes
            changed = True

        if changed and not args.dry_run:
            backup_dir = BACKUP_ROOT / datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(actor_path, backup_dir / actor_path.name)
            save_json(actor_path, actor_skills)
            print(f"  [写入] {actor_path.name}（备份：{backup_dir.relative_to(PROJECT)}）")

    print(f"\n===== 汇总 =====")
    print(f"配置轨道：{total_tracks}（库匹配 {library_hits} / 生成 {total_tracks - library_hits}）")
    for line in report:
        print(f"  {line}")
    if args.dry_run:
        print("（dry-run：未写盘）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
