#!/usr/bin/env python3
"""Add the smoke3d module set (3D scenes + GodotPhysics3D) to build-engine.sh."""
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
if 'smoke3d)' in s:
    print('smoke3d already present'); sys.exit(0)
old = """  smoke)
    module_flags=(modules_enabled_by_default=no
                  module_gdscript_enabled=yes
                  module_text_server_fb_enabled=yes
                  disable_3d=yes
                  disable_xr=yes
                  disable_advanced_gui=yes)
    ;;"""
new = old + """
  smoke3d)
    module_flags=(modules_enabled_by_default=no
                  module_gdscript_enabled=yes
                  module_text_server_fb_enabled=yes
                  module_freetype_enabled=yes
                  builtin_freetype=yes
                  module_godot_physics_3d_enabled=yes
                  disable_physics_3d=no
                  module_navigation_3d_enabled=yes
                  disable_3d=no
                  disable_xr=yes
                  disable_advanced_gui=no)
    echo 'GODOT_PS5_3D_MODULE_SET=1'
    ;;"""
assert old in s
p.write_text(s.replace(old, new, 1))
print('smoke3d module set added')
