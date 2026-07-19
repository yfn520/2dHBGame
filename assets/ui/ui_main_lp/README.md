FrameRonin Godot UI Scene Package

Screen: ui_main_lp
Design size: 1920 x 1080
Nodes: 15
Textures: 18
Masks: 0
Fonts: 0

Files:
- assets/ui/ui_main_lp.tscn: Godot 4 scene.
- assets/ui/ui_main_lp/background/*: optional background image.
- assets/ui/ui_main_lp/textures/*: static and state textures.
- assets/ui/ui_main_lp/masks/*.png: alpha masks for dynamic image clipping.
- assets/ui/ui_main_lp/fonts/*: optional font files.
- assets/ui/ui_main_lp/ui_scene_manifest.json: node and binding manifest.

Usage:
1. Extract this ZIP directly into your Godot 4.7 project root.
2. Godot will import the assets automatically.
3. Instance the scene under a CanvasLayer or Control.
4. Bind runtime values using scene-unique names:
   %player_avatar.texture = avatar_texture
   %player_name.text = character.display_name
   %player_hp.value = character.hp
   %inventory_button.pressed.connect(_on_inventory_pressed)

This package contains no GDScript. Connect signals and set values at runtime.