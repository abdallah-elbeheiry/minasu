# Aqwabor Engine (minasu port)

> **Status: Unfinished prototype.** This is an experimental rewrite/port of
> [AqwaborEngine](https://github.com/abdallah-elbeheiry/AqwaborEngine) (Go) into
> [Odin](https://odin-lang.org). It is a work in progress and not production-ready.

## Why the rewrite

The original engine was written in Go, which relies on a garbage collector.
For a game engine where predictable frame times and manual resource lifetimes
matter, GC pauses and implicit allocations became a liability. This port moves
the engine to Odin — a language with no garbage collector, explicit allocators,
and deterministic memory management — to eliminate those issues.

## What's here

- `aqwabor/` — engine packages (window, image, input, logx, ...)
- `resources/` — demo assets
- `examples/windowdemo/` — small window + image + input demo

## Building

Requires Odin (dev nightly) and SDL3 development libraries.

```
odin build aqwabor/examples/windowdemo -collection:aqwabor=aqwabor
```

Run with a Wayland session on Linux:

```
SDL_VIDEODRIVER=wayland ./windowdemo
```

## Tests

```
odin test aqwabor -collection:aqwabor=aqwabor
```

## License

Unspecified. See upstream project for original licensing.
