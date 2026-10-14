; Sending chat commands to PoE and (re)registering per-button hotkeys

global Busy := false
global ActiveHotkeys := []

IsPoeActive(*) {
    return WinActive("ahk_class POEWindowClass")
}

; Works as a Click callback (ctrl, info) and as a Hotkey callback (name).
SendChat(cmd, *) {
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
        A_Clipboard := cmd
        if ClipWait(1) {
            SendInput("{Enter}")
            Sleep(20)
            SendInput("^v")
            Sleep(20)
            SendInput("{Enter}")
            Sleep(50)
        }
    }
    A_Clipboard := saved
    Busy := false
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
