# Blender modelling and assets

Read before using the Blender MCP to make models for the game.

- **Low-Poly & Scale:** Keep geometry clean and low-poly. Remember that **1 Blender unit = 1 Roblox stud**. Always design items to scale (e.g., a crate should be around 4x4x4 studs).
- **Origin Points:** Keep the object's origin point centered at the base (bottom-center) of the model so it aligns properly when imported or scripted into Roblox Studio.
- **No Complex Materials:** Stick to simple vertex colors or basic principled BSDF materials with flat colors. Roblox Studio handles textures and materials natively via imports.
- **Naming Conventions:** Name objects clearly (e.g., `Prop_WoodenCrate`, `Scenery_PineTree`) so they can be easily referenced or exported.
- **Exporting:** Once a model is generated in Blender, remind the owner to export it as an `.fbx` file, check its transforms (Apply Scale/Rotation), and use the Roblox Studio 3D Importer.
- **Files:** Blender sources and exports live in `models/` (`models/karts.blend` holds the karts and wheels). The MCP can export the FBX itself; only the Studio 3D Importer step needs the owner.
- **Karts and wheels:** model karts with the front towards Blender +Y, X right, Z up, ground at z 0 (the hitbox centre is at z 1.1). Split each model into one object per colour role (e.g. `F1_Paint`, `F1_Carbon`, `F1_Trim`) so Roblox can paint them. Wheels: 2 units across, axle along X, centred on the origin. Export with `axis_forward='-Z', axis_up='Y', bake_space_transform=True` so Blender +Y becomes Roblox -Z (the front). After importing, check the size and position against the Blender bounding box and fix them in Studio before making the template (see `docs/karts-characters.md`). With these settings the Studio importer brings Blender models in 100× too big and turned 180° (front at +Z): divide each MeshPart's Size by 100, rotate it 180° around Y and place it at its Blender bounding-box centre.
