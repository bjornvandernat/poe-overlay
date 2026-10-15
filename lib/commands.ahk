; Sending chat commands to PoE and (re)registering per-button hotkeys

global Busy := false
global ActiveHotkeys := []

IsPoeActive(*) {
    return WinActive("ahk_class POEWindowClass")
}

; Extra window criteria the overlay should also show over (WinTitle strings, e.g. "ahk_exe idea64.exe").
; Empty by default; a local, git-ignored lib\dev.ahk can add to it. Sending keys and hotkeys still
; require PoE (IsPoeActive).
global ExtraTargets := []

IsOverlayTarget() {
    if IsPoeActive()
        return true
    for t in ExtraTargets
        if WinActive(t)
            return true
    return false
}

; Puts text on the clipboard, sends the keys (the last one is followed by a longer pause), then restores
; the clipboard. Works as a Click callback (ctrl, info) and as a Hotkey callback (name) via the wrappers.
PasteKeys(text, keys*) {
    global Busy
    if Busy || !IsPoeActive()
        return
    Busy := true
    saved := ClipboardAll()
    try {
        ; let go of modifiers from a hotkey so Enter / Ctrl+V aren't combined with them
        for k in ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
            KeyWait(k, "T1")
        A_Clipboard := ""
        A_Clipboard := text
        if ClipWait(1) {
            for i, k in keys {
                SendInput(k)
                Sleep(i < keys.Length ? 20 : 50)
            }
        }
    }
    A_Clipboard := saved
    Busy := false
}

; Chat command: Enter, paste, Enter
SendChat(cmd, *) {
    PasteKeys(cmd, "{Enter}", "^v", "{Enter}")
}

; Stash search: Ctrl+F, paste
SendSearch(search, *) {
    PasteKeys(search, "^f", "^v")
}

RegisterHotkeys() {
    global ActiveHotkeys
    HotIf(IsPoeActive)
    for hk in ActiveHotkeys
        try Hotkey(hk, "Off")
    ActiveHotkeys := []
    for b in Buttons {
        if b["hotkey"] = "" || !b["enabled"]
            continue
        try {
            Hotkey("$" b["hotkey"], SendChat.Bind(b["command"]), "On")
            ActiveHotkeys.Push("$" b["hotkey"])
        }
    }
    if Settings["widgetsEnabled"] && WidgetsHotkey != "" {
        try {
            Hotkey("$" WidgetsHotkey, (*) => ToggleWidgets(), "On")
            ActiveHotkeys.Push("$" WidgetsHotkey)
        }
    }
    HotIf()
}

; "^!h" -> "Ctrl+Alt+H"
PrettyHotkey(hk) {
    if hk = ""
        return ""
    out := ""
    i := 1
    while i <= StrLen(hk) {
        c := SubStr(hk, i, 1)
        if c = "^"
            out .= "Ctrl+"
        else if c = "!"
            out .= "Alt+"
        else if c = "+"
            out .= "Shift+"
        else if c = "#"
            out .= "Win+"
        else
            break
        i++
    }
    return out StrUpper(SubStr(hk, i, 1)) SubStr(hk, i + 1)
}
