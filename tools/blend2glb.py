import bpy, sys, os
src, dst = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=src)
base = os.path.dirname(src)
for o in list(bpy.data.objects):
    if o.type not in ('MESH', 'ARMATURE', 'EMPTY'):
        bpy.data.objects.remove(o, do_unlink=True)

def find_image(img):
    cands = [bpy.path.abspath(img.filepath), os.path.join(base, os.path.basename(img.filepath)),
             os.path.join(base, 'Textures', os.path.basename(img.filepath))]
    for c in cands:
        if c and os.path.isfile(c):
            return c
    return None

for m in bpy.data.materials:
    color = list(m.diffuse_color)
    img_path = None
    if m.use_nodes and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                img_path = find_image(n.image) or img_path
            if n.type == 'BSDF_PRINCIPLED':
                color = list(n.inputs['Base Color'].default_value)
        for n in m.node_tree.nodes:
            if n.type == 'BSDF_DIFFUSE' and not img_path and m.diffuse_color[:3] == (0.8, 0.8, 0.8):
                color = list(n.inputs['Color'].default_value)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Roughness'].default_value = 0.8
    bsdf.inputs['Base Color'].default_value = color
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    if img_path:
        tex = nt.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(img_path)
        tex.interpolation = 'Closest'
        nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    print("MAT", m.name, "img" if img_path else "col", os.path.basename(img_path) if img_path else [round(c, 2) for c in color[:3]])

bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_image_format='AUTO', export_apply=True)
print("OK", os.path.basename(dst))
