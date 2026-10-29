# Aqwabor

A 2D game engine in Odin, ported from the Go implementation to drop the garbage
collector. Storage and scheduling stay separate: a component store says where a
value lives; what runs is the awake partition of a store, a timer coming due,
or a set a system keeps for itself.

Three things a caller touches, and everything else is behind them:

```
Window  = a surface, a device, a frame callback
GPU     = Begin, SetCamera, Draw*, End
World   = entities, plain components, and what is awake
```

```odin
w := ecs.new_world()
pos := ecs.must_register(w, Position)

e := ecs.create(w)
ecs.set(pos, e, Position{x = 1})
ecs.wake(pos, e)

ecs.each(pos, proc(e: ecs.Entity, p: ^Position) {
    p.x += 1
})
```

## Packages

| Package | Role |
|---|---|
| `ecs` | Generational entities, dense PoD stores, awake partition, timers, sets |
| `schedulers` | Deterministic master clock, job rates, access-declared stages |
| `camera` | 2D view transform as an ECS component |
| `render` | WebGPU submission, scene, sprites, cells, strokes |
| `window` | GLFW surface and frame callback |
| `input` | Actions, bindings, headless injection |
| `sound` | Mixer and miniaudio output |
| `triangulate` | Ear-clipping for closed rings |
| `logx` | Engine logging |

The engine widget toolkit from the Go tree (`gogpu/ui`) is not part of this
port. Minasu is the GUI that will sit on top of this collection later.

## Building

From the minasu root:

```
odin test aqwabor/ecs -collection:aqwabor=aqwabor
odin test aqwabor/schedulers -collection:aqwabor=aqwabor
odin build aqwabor/cmd/aqwabor -collection:aqwabor=aqwabor -out:aqwabor
```
