package input

// Key identifies a physical keyboard key.
//
// The numeric values intentionally match the gogpu input package
// so the gogpu backend can pass key codes through without a conversion table.
// They are stable for a given engine version and are only used internally
// as opaque identifiers.
Key :: enum u16 {
    Unknown,       // 0

    // KeyF1 Function keys
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,  // 1-12

    // Key0 Number keys
    Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9,  // 13-22

    // KeyA Letter keys
    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,  // 23-48

    // KeySpace Special keys
    Space, Enter, Escape, Backspace, Tab, CapsLock,  // 49-54
    ShiftLeft, ShiftRight, ControlLeft, ControlRight, AltLeft, AltRight,  // 55-60
    SuperLeft, SuperRight,  // 61-62  Windows/Command key

    // KeyUp Arrow keys
    Up, Down, Left, Right,  // 63-66

    // KeyInsert Navigation keys
    Insert, Delete, Home, End, PageUp, PageDown,  // 67-72

    // KeyMinus Punctuation
    Minus, Equal, LeftBracket, RightBracket, Backslash, Semicolon, Apostrophe, Grave, Comma, Period, Slash,  // 73-83

    // KeyNumpad0 Numpad
    Numpad0, Numpad1, Numpad2, Numpad3, Numpad4, Numpad5, Numpad6, Numpad7, Numpad8, Numpad9,  // 84-93
    NumpadAdd, NumpadSubtract, NumpadMultiply, NumpadDivide, NumpadEnter, NumpadDecimal, NumLock,  // 94-100

    // KeyPrintScreen Other
    PrintScreen, ScrollLock, Pause, Cancel,  // 101-104  Cancel: Win32 Ctrl+Break (VK_CANCEL); distinct from Pause

    Count,  // 105  Number of keys
}

// MouseButton identifies a mouse button.
//
// The numeric values intentionally match the gogpu input package.
MouseButton :: enum u8 {
    Left,   // 0
    Right,  // 1
    Middle, // 2
    B4,     // 3
    B5,     // 4
    Count,  // 5
}
