#!/bin/bash
# Fetch the engine + game logs after a launch attempt.
H="${PS5_HOST:?set PS5_HOST to the console address}"
for f in /data/GodotPS5/gles3-runtime.log /data/GodotPS5/gles3-stdout.log /data/GodotPS5/gles3-stderr.log /data/GodotPS5/engine-boot-v022.log; do
  echo "===== $f ====="
  curl -s -m 10 "ftp://$H:2121$f" | tail -35
  echo
done
echo "===== saltline_boot.log ====="
curl -s -m 10 "ftp://$H:2121/data/GodotPS5/userdata/godot_app_userdata_Saltline/saltline_boot.log" | tail -30
