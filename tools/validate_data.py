#!/usr/bin/env python3
"""data/*.json 数据契约校验（Harness 架构护栏）。

背景：data/*.json 由网页工作台（../frontend）编译发布，本侧只读。历史上多次出现
手改失配 / trailing-comma 损坏 / 资产路径悬空等问题，本脚本把「数据坏了」拦在加载阶段。

校验项：
  1. 全部 data/*.json 可 json.load（捕获语法损坏）
  2. dialogues.json：format=='timeline' 的条目 clips 每项含 id/kind/startMs；
     kind 属于合法枚举；actions 每项含 type
  3. npcs.json：asset 指向的目录与 portrait.png 存在
  4. characters.json：scene / character_config 路径存在
  5. quests.json：giver_npc_id / turn_in_npc_id 为整数

用法：python tools/validate_data.py   （全部通过退出码 0，否则 1）
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent  # hengban-2/
DATA = PROJECT / "data"

VALID_CLIP_KINDS = {
    "black_screen", "subtitle", "video", "line", "narration",
    "stage_action", "choice", "event",
}


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def check_json_loadable(path: Path, errors: list[str]) -> dict | list | None:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:  # noqa: BLE001
        fail(errors, f"{path.relative_to(PROJECT)} JSON 解析失败：{exc}")
        return None


def check_dialogues(errors: list[str]) -> None:
    path = DATA / "dialogues.json"
    if not path.is_file():
        fail(errors, "缺少 data/dialogues.json")
        return
    data = check_json_loadable(path, errors)
    if not isinstance(data, dict):
        return
    for key, entry in data.items():
        if not isinstance(entry, dict):
            fail(errors, f"dialogues.json[{key}] 不是对象")
            continue
        if entry.get("format") != "timeline":
            continue
        clips = entry.get("clips")
        if not isinstance(clips, list):
            fail(errors, f"dialogues.json[{key}] timeline 缺少 clips 数组")
            continue
        for index, clip in enumerate(clips):
            if not isinstance(clip, dict):
                fail(errors, f"dialogues.json[{key}].clips[{index}] 不是对象")
                continue
            for field in ("id", "kind", "startMs"):
                if field not in clip:
                    fail(errors, f"dialogues.json[{key}].clips[{index}] 缺少字段 {field}")
            kind = clip.get("kind")
            if kind is not None and kind not in VALID_CLIP_KINDS:
                fail(errors, f"dialogues.json[{key}].clips[{index}] 非法 kind：{kind}")
            actions = clip.get("actions")
            if actions is not None:
                if not isinstance(actions, list):
                    fail(errors, f"dialogues.json[{key}].clips[{index}].actions 不是数组")
                else:
                    for ai, action in enumerate(actions):
                        if not isinstance(action, dict) or "type" not in action:
                            fail(errors, f"dialogues.json[{key}].clips[{index}].actions[{ai}] 缺少 type")


def check_npcs(errors: list[str]) -> None:
    path = DATA / "npcs.json"
    if not path.is_file():
        return
    data = check_json_loadable(path, errors)
    if not isinstance(data, dict):
        return
    for npc_id, npc in data.items():
        if not isinstance(npc, dict):
            continue
        asset = str(npc.get("asset", ""))
        if not asset:
            continue
        rel = asset.removeprefix("res://")
        asset_dir = PROJECT / rel
        if not asset_dir.is_dir():
            fail(errors, f"npcs.json[{npc_id}] asset 目录不存在：{rel}")
            continue
        if not (asset_dir / "portrait.png").is_file():
            fail(errors, f"npcs.json[{npc_id}] 缺少 portrait.png：{rel}/portrait.png")


def check_characters(errors: list[str]) -> None:
    path = DATA / "characters.json"
    if not path.is_file():
        return
    data = check_json_loadable(path, errors)
    if not isinstance(data, dict):
        return
    for char_id, char in data.items():
        if not isinstance(char, dict):
            continue
        for field in ("scene", "character_config"):
            rel = str(char.get(field, ""))
            if not rel:
                continue
            if not (PROJECT / rel.removeprefix("res://")).is_file():
                fail(errors, f"characters.json[{char_id}].{field} 文件不存在：{rel}")


def check_quests(errors: list[str]) -> None:
    path = DATA / "quests.json"
    if not path.is_file():
        return
    data = check_json_loadable(path, errors)
    if not isinstance(data, dict):
        return
    for quest_id, quest in data.items():
        if not isinstance(quest, dict):
            continue
        for field in ("giver_npc_id", "turn_in_npc_id"):
            value = quest.get(field)
            if value is not None and not isinstance(value, int):
                fail(errors, f"quests.json[{quest_id}].{field} 必须是整数，实际 {type(value).__name__}")


def check_music(errors: list[str]) -> None:
    """校验网页音乐编排台发布的 music.json 与关卡 BGM 引用。

    music.json 在首次发布前允许不存在；发布后必须满足完整的可追溯契约。
    """
    path = DATA / "music.json"
    if path.is_file():
        data = check_json_loadable(path, errors)
        if isinstance(data, dict):
            if data.get("format") != "frame-ronin-music-v1":
                fail(errors, "music.json format 必须是 frame-ronin-music-v1")
            if not isinstance(data.get("version"), int):
                fail(errors, "music.json version 必须是整数")
            tracks = data.get("tracks")
            if not isinstance(tracks, dict):
                fail(errors, "music.json tracks 必须是对象")
            else:
                for scene_key, track in tracks.items():
                    if not isinstance(track, dict):
                        fail(errors, f"music.json.tracks[{scene_key}] 必须是对象")
                        continue
                    if str(track.get("scene_key", "")) != str(scene_key):
                        fail(errors, f"music.json.tracks[{scene_key}].scene_key 必须与键一致")
                    music_path = str(track.get("path", ""))
                    if not music_path:
                        fail(errors, f"music.json.tracks[{scene_key}] 缺少 path")
                    elif not (PROJECT / music_path.removeprefix("res://")).is_file():
                        fail(errors, f"music.json.tracks[{scene_key}] 音乐文件不存在：{music_path}")
                    source = str(track.get("source", ""))
                    if source not in {"generated", "derived"}:
                        fail(errors, f"music.json.tracks[{scene_key}].source 必须是 generated 或 derived")
                    if source == "derived":
                        if not str(track.get("derived_from", "")):
                            fail(errors, f"music.json.tracks[{scene_key}] 改写轨缺少 derived_from")
                        noise = track.get("init_noise_level")
                        if not isinstance(noise, (int, float)) or not 0.1 <= float(noise) <= 1.0:
                            fail(errors, f"music.json.tracks[{scene_key}] 改写轨 init_noise_level 必须在 0.1~1.0")

    levels_path = DATA / "levels.json"
    if not levels_path.is_file():
        return
    levels = check_json_loadable(levels_path, errors)
    if not isinstance(levels, dict):
        return
    for level_id, level in levels.items():
        if not isinstance(level, dict):
            continue
        bgm = str(level.get("bgm", ""))
        if bgm and not (PROJECT / bgm.removeprefix("res://")).is_file():
            fail(errors, f"levels.json[{level_id}].bgm 音乐文件不存在：{bgm}")


def check_skill_audio_paths(errors: list[str]) -> None:
    """data/skills/actors/*.json 中的音效路径必须落地（play_sound 节点 + 弹道/命中音效字段）。"""
    actors_dir = DATA / "skills" / "actors"
    if not actors_dir.is_dir():
        return
    for path in sorted(actors_dir.glob("*.json")):
        data = check_json_loadable(path, errors)
        if not isinstance(data, dict):
            continue
        for skill_id, skill in data.items():
            if not isinstance(skill, dict):
                continue
            for node_index, node in enumerate(skill.get("nodes", [])):
                if not isinstance(node, dict):
                    continue
                candidates: list[tuple[str, dict]] = []
                if node.get("type") == "play_sound":
                    candidates.append(("play_sound", node))
                for field in ("spawn_audio", "flight_audio", "hit_audio", "on_hit_audio"):
                    cfg = node.get(field)
                    if isinstance(cfg, dict):
                        candidates.append((field, cfg))
                for field_name, cfg in candidates:
                    audio_path = str(cfg.get("audio_path", ""))
                    if not audio_path:
                        fail(errors, f"skills/actors/{path.name}[{skill_id}].nodes[{node_index}].{field_name} 缺少 audio_path")
                        continue
                    if not (PROJECT / audio_path.removeprefix("res://")).is_file():
                        fail(errors, f"skills/actors/{path.name}[{skill_id}].nodes[{node_index}].{field_name} 音效文件不存在：{audio_path}")


def check_echo_spawns(errors: list[str]) -> None:
    """章节回响表守卫：id 存在、Boss 带 echo 特征、坐标在画布内、chapters 回响 Boss 指向一致。"""
    path = DATA / "echo_spawns.json"
    if not path.is_file():
        return  # 回响未配置时不报错（功能可选）
    data = check_json_loadable(path, errors)
    if not isinstance(data, dict):
        return
    enemies = check_json_loadable(DATA / "enemies.json", errors)
    chapters = check_json_loadable(DATA / "chapters.json", errors)
    if not isinstance(enemies, dict) or not isinstance(chapters, dict):
        return
    levels = data.get("levels")
    if not isinstance(levels, dict):
        fail(errors, "echo_spawns.json levels 必须是对象")
        return
    for level_id, table in levels.items():
        if not isinstance(table, dict):
            fail(errors, f"echo_spawns[{level_id}] 必须是对象")
            continue
        chapter_id = str(table.get("chapter_id", ""))
        entries = []
        for group in table.get("groups", []) or []:
            if isinstance(group, dict):
                entries.append(("group", int(group.get("enemy_id", 0)), float(group.get("x", 0)), float(group.get("y", 0))))
        for key in ("elite", "boss"):
            single = table.get(key)
            if isinstance(single, dict):
                entries.append((key, int(single.get("enemy_id", 0)), float(single.get("x", 0)), float(single.get("y", 0))))
        for kind, enemy_id, x, y in entries:
            enemy = enemies.get(str(enemy_id))
            if not isinstance(enemy, dict):
                fail(errors, f"echo_spawns[{level_id}].{kind} 敌人不存在: {enemy_id}")
                continue
            if kind == "boss":
                traits = enemy.get("traits") or []
                if not enemy.get("is_boss") or "echo" not in traits:
                    fail(errors, f"echo_spawns[{level_id}].boss {enemy_id} 必须是 is_boss 且 traits 含 echo")
                if not enemy.get("echo_drop_items"):
                    fail(errors, f"echo_spawns[{level_id}].boss {enemy_id} 缺少 echo_drop_items（防农穿）")
                unique_ids = {
                    int(drop.get("item_id", 0))
                    for drop in enemy.get("drop_items", [])
                    if isinstance(drop, dict) and float(drop.get("chance", 0.0)) >= 0.999
                }
                repeat_ids = {
                    int(drop.get("item_id", 0))
                    for drop in enemy.get("echo_drop_items", [])
                    if isinstance(drop, dict) and abs(float(drop.get("chance", 0.0)) - 0.08) < 0.0001
                }
                # 部分原 Boss 没有 chance=1 的具名装备；这类只校验 farming 表。
                if unique_ids and not unique_ids.intersection(repeat_ids):
                    fail(errors, f"echo_spawns[{level_id}].boss {enemy_id} 必须保留首杀唯一掉落及其 0.08 回响复刷掉落")
                chapter = chapters.get(chapter_id, {})
                if int(chapter.get("echo_boss_enemy_id", 0)) != enemy_id:
                    fail(errors, f"chapters[{chapter_id}].echo_boss_enemy_id 与回响表 boss 不一致")
            if kind == "elite":
                traits = enemy.get("traits") or []
                if "echo" not in traits:
                    fail(errors, f"echo_spawns[{level_id}].elite {enemy_id} traits 必须含 echo")
            if not (0 <= x <= 4096 and 0 <= y <= 864):
                fail(errors, f"echo_spawns[{level_id}].{kind} 坐标越界: ({x}, {y})")


def check_skill_fx_bundles(errors: list[str]) -> None:
    """assets/effects/skill_fx/*/skill_fx_bundle.json 的资源路径必须落地（atlas/scene）。"""
    fx_root = PROJECT / "assets" / "effects" / "skill_fx"
    if not fx_root.is_dir():
        return
    for manifest_path in sorted(fx_root.glob("*/skill_fx_bundle.json")):
        data = check_json_loadable(manifest_path, errors)
        if not isinstance(data, dict):
            continue
        if data.get("format") != "frame-ronin-skill-fx-bundle-v1":
            fail(errors, f"{manifest_path.relative_to(PROJECT)} format 不是 frame-ronin-skill-fx-bundle-v1")
            continue
        tracks = data.get("tracks")
        if not isinstance(tracks, list) or not tracks:
            fail(errors, f"{manifest_path.relative_to(PROJECT)} 缺少 tracks")
            continue
        for track in tracks:
            if not isinstance(track, dict):
                continue
            asset = track.get("asset")
            track_id = track.get("id", "?")
            # 网页侧 hydrate 前提：loadAndHydrateDirectorState 会丢弃缺 phase/trigger 的
            # checkpoint（hasMalformedTracks），并从 bundle 重建——所以 bundle 轨道必须齐备。
            if not str(track.get("phase", "")):
                fail(errors, f"skill_fx/{data.get('bundle_id')}[{track_id}] 缺 phase（网页特效导演无法 hydrate）")
            trigger = track.get("trigger")
            if not isinstance(trigger, dict) or not str(trigger.get("type", "")):
                fail(errors, f"skill_fx/{data.get('bundle_id')}[{track_id}] 缺 trigger.type（网页特效导演无法 hydrate）")
            if not isinstance(asset, dict):
                fail(errors, f"skill_fx/{data.get('bundle_id')}[{track_id}] 缺少 asset")
                continue
            for field in ("atlas_path", "scene_path"):
                rel = str(asset.get(field, ""))
                if not rel:
                    fail(errors, f"skill_fx/{data.get('bundle_id')}[{track_id}].asset 缺少 {field}")
                elif not (PROJECT / rel.removeprefix("res://")).is_file():
                    fail(errors, f"skill_fx/{data.get('bundle_id')}[{track_id}].{field} 文件不存在：{rel}")
            if int(asset.get("frame_count") or 0) < 1:
                fail(errors, f"skill_fx/{data.get('bundle_id')}[{track_id}].frame_count 必须 ≥ 1")
            if float(asset.get("fps") or 0) <= 0:
                fail(errors, f"skill_fx/{data.get('bundle_id')}[{track_id}].fps 必须 > 0")


def check_play_effect_scenes(errors: list[str]) -> None:
    """data/skills/actors/*.json 中 play_effect 节点的 scene 路径必须存在（空值跳过，那是待配置）。"""
    actors_dir = DATA / "skills" / "actors"
    if not actors_dir.is_dir():
        return
    for path in sorted(actors_dir.glob("*.json")):
        data = check_json_loadable(path, errors)
        if not isinstance(data, dict):
            continue
        for skill_id, skill in data.items():
            if not isinstance(skill, dict):
                continue
            for node_index, node in enumerate(skill.get("nodes", [])):
                if not isinstance(node, dict) or node.get("type") != "play_effect":
                    continue
                scene = str(node.get("scene", ""))
                if not scene:
                    continue
                if not (PROJECT / scene.removeprefix("res://")).is_file():
                    fail(errors, f"skills/actors/{path.name}[{skill_id}].nodes[{node_index}] play_effect 场景不存在：{scene}")


def check_skill_fx_bundle_skill_ids(errors: list[str], warnings: list[str], known_skill_ids: set[str]) -> None:
    """bundle 的 skill_id 应能在 data/skills/actors/*.json 里找到，否则网页编排台匹配不上。

    孤儿 bundle（技能已删/改名）无害但永远不生效，降为警告，不让存量遗留把套件弄红。
    """
    fx_root = PROJECT / "assets" / "effects" / "skill_fx"
    if not fx_root.is_dir():
        return
    for manifest_path in sorted(fx_root.glob("*/skill_fx_bundle.json")):
        try:
            data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        except Exception:  # noqa: BLE001
            continue
        if not isinstance(data, dict):
            continue
        skill_id = str(data.get("skill_id", ""))
        if not skill_id:
            errors.append(f"{manifest_path.relative_to(PROJECT)} 缺 skill_id")
        elif skill_id not in known_skill_ids:
            warnings.append(f"孤儿特效包：skill_fx/{data.get('bundle_id')} 的 skill_id {skill_id} 已不在 data/skills/actors 中（网页与 Godot 都不会加载它）")


def collect_skill_ids() -> set[str]:
    ids: set[str] = set()
    actors_dir = DATA / "skills" / "actors"
    if not actors_dir.is_dir():
        return ids
    for path in actors_dir.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8-sig"))
        except Exception:  # noqa: BLE001
            continue
        if isinstance(data, dict):
            ids.update(str(key) for key in data.keys())
    return ids


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    if not DATA.is_dir():
        print(f"[validate_data] 缺少目录：{DATA}", file=sys.stderr)
        return 1
    for path in sorted(DATA.glob("*.json")):
        check_json_loadable(path, errors)
    check_dialogues(errors)
    check_npcs(errors)
    check_characters(errors)
    check_quests(errors)
    check_music(errors)
    check_skill_audio_paths(errors)
    check_skill_fx_bundles(errors)
    check_echo_spawns(errors)
    check_skill_fx_bundle_skill_ids(errors, warnings, collect_skill_ids())
    check_play_effect_scenes(errors)
    for message in warnings:
        print(f"[validate_data] 警告：{message}")
    if errors:
        print(f"[validate_data] FAIL：{len(errors)} 个问题")
        for message in errors:
            print(f"  - {message}")
        return 1
    print("[validate_data] OK：data/*.json 全部通过契约校验")
    return 0


if __name__ == "__main__":
    sys.exit(main())
