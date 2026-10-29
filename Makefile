COLLECTION := -collection:aqwabor=aqwabor

.PHONY: dev build test bench demo-window demo-flappy clean

dev:
	odin run aqwabor/examples/windowdemo $(COLLECTION)

demo-window:
	odin run aqwabor/examples/windowdemo $(COLLECTION)

demo-flappy:
	odin run aqwabor/examples/flappybird $(COLLECTION)

build:
	odin build aqwabor $(COLLECTION) -out:/tmp/aqwabor

test:
	odin test aqwabor/ecs $(COLLECTION)

bench:
	odin run aqwabor/bench $(COLLECTION) -o:speed

clean:
	rm -f aqwabor aqwabor.bin /tmp/aqwabor /tmp/windowdemo /tmp/renderdemo
