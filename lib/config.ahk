; Settings + button list, persisted in settings.ini

global CFG_FILE := A_ScriptDir "\settings.ini"
global ICON_DIR := A_ScriptDir "\icons"
global SCALE_MIN := 50    ; percent
global SCALE_MAX := 500
global BUTTON_SIZE := 48   ; px at 100% scale
global COG_SIZE := 24      ; the settings cog never scales
global Settings := Map("x", 20, "y", 200, "vertical", 0, "scale", 100, "locked", 0)
global Buttons := []   ; Array of Map(name, icon, command, hotkey)

NewButton(name, icon, command, hotkey := "", enabled := 1) {
    return Map("name", name, "icon", icon, "command", command, "hotkey", hotkey, "enabled", enabled)
}

EnabledCount() {
    n := 0
    for b in Buttons
        if b["enabled"]
            n++
    return n
}

DefaultButtons() {
    return [
        NewButton("Hideout", "hideout.png", "/hideout"),
        NewButton("Guild Hideout", "guild.png", "/guild"),
        NewButton("Kingsmarch", "kingsmarch.png", "/kingsmarch"),
        NewButton("Menagerie", "menagerie.png", "/menagerie"),
        NewButton("Monastery", "monastery.png", "/monastery"),
        NewButton("Sanctum", "sanctum.png", "/sanctum"),
        NewButton("Rogue Harbour", "heist.png", "/heist"),
        NewButton("Mine Encampment", "delve.png", "/delve"),
        NewButton("The Sovereign", "boat.png", "/boat"),
    ]
}

LoadConfig() {
    global Settings, Buttons
    if !FileExist(CFG_FILE) {
        Buttons := DefaultButtons()
        SaveConfig()
        return
    }
    for key, def in Settings.Clone()
        Settings[key] := Integer(IniRead(CFG_FILE, "General", key, def))
    Settings["scale"] := Max(SCALE_MIN, Min(SCALE_MAX, Settings["scale"]))

    Buttons := []
    count := Integer(IniRead(CFG_FILE, "General", "count", 0))
    Loop count {
        sec := "Button" A_Index
        Buttons.Push(NewButton(
            IniRead(CFG_FILE, sec, "name", "Button"),
            IniRead(CFG_FILE, sec, "icon", "plus.png"),
            IniRead(CFG_FILE, sec, "command", "/"),
            IniRead(CFG_FILE, sec, "hotkey", ""),
            Integer(IniRead(CFG_FILE, sec, "enabled", 1))))   ; missing value = enabled
    }
}

SaveConfig() {
    try FileDelete(CFG_FILE)
    for key, val in Settings
        IniWrite(val, CFG_FILE, "General", key)
    IniWrite(Buttons.Length, CFG_FILE, "General", "count")
    for i, b in Buttons {
        sec := "Button" i
        for key in ["name", "icon", "command", "hotkey", "enabled"]
            IniWrite(b[key], CFG_FILE, sec, key)
    }
}

; Icons are stored as a bare file name (inside icons\) or an absolute path.
ResolveIcon(icon) {
    return InStr(icon, ":") ? icon : ICON_DIR "\" icon
}

CloneButtons(list) {
    out := []
    for b in list
        out.Push(b.Clone())
    return out
}
