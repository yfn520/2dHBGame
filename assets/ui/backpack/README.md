FrameRonin Godot UI Scene Package

Screen: backpack
Design size: 760 x 515
Nodes: 12
Textures: 1
Masks: 0
Fonts: 0

Files:
- assets/ui/backpack.tscn: Godot 4 scene.
- assets/ui/backpack/background/*: optional background image.
- assets/ui/backpack/textures/*: static and state textures.
- assets/ui/backpack/masks/*.png: alpha masks for dynamic image clipping.
- assets/ui/backpack/fonts/*: optional font files.
- assets/ui/backpack/ui_scene_manifest.json: node and binding manifest.

Usage:
1. Extract this ZIP directly into your Godot 4.7 project root.
2. Godot will import the assets automatically.
3. Instance the scene under a CanvasLayer or Control.
4. Bind runtime values using scene-unique names:
   %player_avatar.texture = avatar_texture
   %player_name.text = character.display_name
   %player_hp.value = character.hp
   %inventory_button.pressed.connect(_on_inventory_pressed)
   %inventory_grid_content.add_child(item_slot)

This package contains no GDScript. Connect signals and set values at runtime.