# Aqwabor

A 2D game engine in Odin, ported from the Go implementation. Storage and
scheduling stay separate: a component store says where a value lives; what runs
is the awake partition of a store, a timer coming due, or a set a system keeps
for itself.

Three things a caller touches, and everything else is behind them:

```
Window  = a surface, a device, a frame callback
GPU     = Begin, SetCamera, Draw*, End
World   = entities, plain components, and what is awake
```

```odin
w := ecs.new_world(allocator)
pos := ecs.must_register(w, Position)

e := ecs.create(w)
ecs.set(pos, e, Position{x = 1})
ecs.wake(pos, e)

for i in 0 ..< len(ecs.rows(pos)) {
    p := &ecs.rows(pos)[i]
    p.x += 1
}
```

## Packages

| Package | Role |
|---|---|
| `ecs` | Generational entities, dense PoD stores, awake partition, timers, sets |
| `schedulers` | Deterministic master clock, job rates, access-declared stages |
| `camera` | 2D view transform |
| `render` | (planned) SDL_gpu submission, scene, sprites, cells, strokes |
| `window` | SDL3 surface, SDL_gpu device, frame callback |
| `input` | Actions, bindings, headless injection |
| `triangulate` | Ear-clipping for closed rings |
| `logx` | Engine logging |

Sound, UI and map rendering from the Go tree are not part of this port yet.
Minasu is the GUI that will sit on top of this collection later.

## Building

From the minasu root:

```
odin test aqwabor/ecs -collection:aqwabor=aqwabor
odin test aqwabor/schedulers -collection:aqwabor=aqwabor
odin build aqwabor -collection:aqwabor=aqwabor -out:/tmp/aqwabor
odin run aqwabor/examples/windowdemo -collection:aqwabor=aqwabor
```

Rendering uses SDL3's GPU API (SDL_gpu), which runs on Vulkan on Linux and
Metal on macOS without MoltenVK.

