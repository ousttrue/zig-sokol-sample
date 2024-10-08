export type LinkType = [string, string];

export type ItemType = {
  name: string,
  links: LinkType[],
};
export type ItemGroupType = {
  name: string,
  url?: string,
  items: ItemType[],
};

export const GROUPS: ItemGroupType[] = [
  {
    name: 'basic',
    items: [
      {
        name: 'clear',
        links: [
          ['zig', 'https://github.com/ousttrue/zig-sokol-sample/blob/master/sokol_examples/clear-sapp.zig'],
          ['c', 'https://github.com/floooh/sokol-samples/blob/master/sapp/clear-sapp.c'],
        ],
      },
      { name: "triangle", links: [], },
      { name: "triangle-bufferless", links: [], },
      { name: "quad", links: [], },
      { name: "bufferoffsets", links: [], },
      { name: "cube", links: [], },
      { name: "noninterleaved", links: [], },
      { name: "texcube", links: [], },
      { name: 'vertexpull', links: [] },
      { name: 'sbuftex', links: [] },
    ],
  },
  {
    name: 'shape',
    items: [
      { name: "shapes", links: [], },
      { name: "shapes-transform", links: [], },
    ]
  },
  {
    name: 'samples',
    items: [
      { name: "offscreen", links: [] },
      { name: 'offscreen-msaa', links: [] },
      { name: "instancing", links: [] },
      { name: 'instancing-pull', links: [] },
      { name: 'mrt', links: [] },
      { name: 'mrt-pixelformats', links: [] },
      { name: 'arraytex', links: [] },
      { name: 'tex3d', links: [] },
      { name: 'dyntex3d', links: [] },
      { name: 'dyntex', links: [] },
      { name: 'basisu', links: [] },
      { name: 'cubemap-jpeg', links: [] },
      { name: 'cubemaprt', links: [] },
      { name: 'miprender', links: [] },
      { name: 'layerrender', links: [] },
      { name: 'primtypes', links: [] },
      { name: 'uvwrap', links: [] },
      { name: 'mipmap', links: [] },
      { name: 'uniformtypes', links: [] },
      { name: 'blend', links: [] },
      { name: 'sdf', links: [] },
      { name: 'shadows', links: [] },
      { name: 'shadows-depthtex', links: [] },
      { name: 'nuklear', links: [] },
      { name: 'nuklear-images', links: [] },
      { name: 'sgl-microui', links: [] },
      { name: 'fontstash', links: [] },
      { name: 'fontstash-layers', links: [] },
      { name: 'events', links: [] },
      { name: 'icon', links: [] },
      { name: "droptest", links: [] },
      { name: 'pixelformats', links: [] },
      { name: 'drawcallperf', links: [] },
      { name: 'saudio', links: [] },
      { name: 'modplay', links: [] },
      { name: 'noentry', links: [] },
      { name: 'restart', links: [] },
      { name: 'loadpng', links: [] },
      { name: 'plmpeg', links: [] },
      { name: 'cgltf', links: [] },
      { name: 'shdfeatures', links: [] },
    ]
  },
  {
    name: 'sgl',
    items: [
      { name: 'sgl', links: [] },
      { name: "sgl-lines", links: [] },
      { name: 'sgl-points', links: [] },
      { name: 'sgl-context', links: [] },
    ]
  },
  {
    name: 'imgui',
    items: [
      { name: 'imgui', links: [] },
      { name: 'imgui-dock', links: [] },
      { name: 'imgui-highdpi', links: [] },
      { name: 'cimgui', links: [] },
      { name: 'imgui-images', links: [] },
      { name: 'imgui-usercallback', links: [] },
    ]
  },
  {
    name: 'debugtext',
    items: [
      { name: 'debugtext', links: [] },
      { name: 'debugtext-printf', links: [] },
      { name: 'debugtext-userfont', links: [] },
      { name: 'debugtext-context', links: [] },
      { name: 'debugtext-layers', links: [] },
    ]
  },
  {
    name: 'ozz',
    items: [
      { name: "ozz-anim", links: [] },
      { name: "ozz-skin", links: [] },
      { name: 'ozz-storagebuffer', links: [] },
    ]
  },
  {
    name: 'spine',
    items: [
      { name: 'spine-simple', links: [] },
      { name: 'spine-inspector', links: [] },
      { name: 'spine-layers', links: [] },
      { name: 'spine-skinsets', links: [] },
      { name: 'spine-switch-skinsets', links: [] },
    ]
  }
];
