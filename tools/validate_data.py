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


def main() -> int:
    errors: list[str] = []
    if not DATA.is_dir():
        print(f"[validate_data] 缺少目录：{DATA}", file=sys.stderr)
        return 1
    for path in sorted(DATA.glob("*.json")):
        check_json_loadable(path, errors)
    check_dialogues(errors)
    check_npcs(errors)
    check_characters(errors)
    check_quests(errors)
    check_skill_audio_paths(errors)
    if errors:
        print(f"[validate_data] FAIL：{len(errors)} 个问题")
        for message in errors:
            print(f"  - {message}")
        return 1
    print("[validate_data] OK：data/*.json 全部通过契约校验")
    return 0


if __name__ == "__main__":
    sys.exit(main())
