# Sector Culling Test

This is an attempt at a visibility culling algorithm in a 2D grid-based world, which may be applied to 3D as well.

It partitions empty space into sectors, and neighboring sectors are linked together. Sectors are marked visible only if they can potentially be seen by the camera.

## Controls

- Left click on map: add/remove walls

- Right click: aim camera

- WASD: move camera
