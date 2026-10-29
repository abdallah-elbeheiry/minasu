package window

import "aqwabor:input"
import SDL "vendor:sdl3"

sdl_key_to_input :: proc(key: SDL.Keycode) -> input.Key {
	switch key {
	case SDL.Keycode(SDL.K_A): return input.Key.A
	case SDL.Keycode(SDL.K_B): return input.Key.B
	case SDL.Keycode(SDL.K_C): return input.Key.C
	case SDL.Keycode(SDL.K_D): return input.Key.D
	case SDL.Keycode(SDL.K_E): return input.Key.E
	case SDL.Keycode(SDL.K_F): return input.Key.F
	case SDL.Keycode(SDL.K_G): return input.Key.G
	case SDL.Keycode(SDL.K_H): return input.Key.H
	case SDL.Keycode(SDL.K_I): return input.Key.I
	case SDL.Keycode(SDL.K_J): return input.Key.J
	case SDL.Keycode(SDL.K_K): return input.Key.K
	case SDL.Keycode(SDL.K_L): return input.Key.L
	case SDL.Keycode(SDL.K_M): return input.Key.M
	case SDL.Keycode(SDL.K_N): return input.Key.N
	case SDL.Keycode(SDL.K_O): return input.Key.O
	case SDL.Keycode(SDL.K_P): return input.Key.P
	case SDL.Keycode(SDL.K_Q): return input.Key.Q
	case SDL.Keycode(SDL.K_R): return input.Key.R
	case SDL.Keycode(SDL.K_S): return input.Key.S
	case SDL.Keycode(SDL.K_T): return input.Key.T
	case SDL.Keycode(SDL.K_U): return input.Key.U
	case SDL.Keycode(SDL.K_V): return input.Key.V
	case SDL.Keycode(SDL.K_W): return input.Key.W
	case SDL.Keycode(SDL.K_X): return input.Key.X
	case SDL.Keycode(SDL.K_Y): return input.Key.Y
	case SDL.Keycode(SDL.K_Z): return input.Key.Z
	case SDL.Keycode(SDL.K_0): return input.Key.Key0
	case SDL.Keycode(SDL.K_1): return input.Key.Key1
	case SDL.Keycode(SDL.K_2): return input.Key.Key2
	case SDL.Keycode(SDL.K_3): return input.Key.Key3
	case SDL.Keycode(SDL.K_4): return input.Key.Key4
	case SDL.Keycode(SDL.K_5): return input.Key.Key5
	case SDL.Keycode(SDL.K_6): return input.Key.Key6
	case SDL.Keycode(SDL.K_7): return input.Key.Key7
	case SDL.Keycode(SDL.K_8): return input.Key.Key8
	case SDL.Keycode(SDL.K_9): return input.Key.Key9
	case SDL.Keycode(SDL.K_SPACE): return input.Key.Space
	case SDL.Keycode(SDL.K_RETURN): return input.Key.Enter
	case SDL.Keycode(SDL.K_ESCAPE): return input.Key.Escape
	case SDL.Keycode(SDL.K_BACKSPACE): return input.Key.Backspace
	case SDL.Keycode(SDL.K_TAB): return input.Key.Tab
	case SDL.Keycode(SDL.K_UP): return input.Key.Up
	case SDL.Keycode(SDL.K_DOWN): return input.Key.Down
	case SDL.Keycode(SDL.K_LEFT): return input.Key.Left
	case SDL.Keycode(SDL.K_RIGHT): return input.Key.Right
	case SDL.Keycode(SDL.K_MINUS): return input.Key.Minus
	case SDL.Keycode(SDL.K_EQUALS): return input.Key.Equal
	}
	return input.Key.Unknown
}
