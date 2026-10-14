; Floating button bar, shown only while PoE (or our own settings window) has focus

global OvGui := ""
global OvGrip := 0
global OvShown := false
global OvW := 0
global OvH := 0
global HoverTips := Map()
global LastTipHwnd := 0

BuildOverlay() {
    global OvGui, OvGrip, OvShown, OvW, OvH, HoverTips
    if OvGui
        OvGui.Destroy()
    OvShown := false
    HoverTips := Map()

    sz := Settings["size"], pad := 3, gap := 3, grip := 8
    vert := Settings["vertical"]
    count := Buttons.Length + 1   ; + cog
    along := pad + grip + pad + count * (sz + gap) - gap + pad
    cross := sz + 2 * pad
    OvW := vert ? cross : along
    OvH := vert ? along : cross

    ; -DPIScale: sizes and positions are real pixels; +E0x08000000 = never take focus on click
    OvGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
    OvGui.BackColor := "1C1C1C"
    OvGui.MarginX := 0, OvGui.MarginY := 0

    OvGrip := OvGui.AddText(vert ? "x0 y0 w" cross " h" grip " +0x100 Background3A3A3A"
                                 : "x0 y0 w" grip " h" cross " +0x100 Background3A3A3A").Hwnd
    HoverTips[OvGrip] := "Drag to move"

    pos := pad + grip + pad
    for b in Buttons {
        ctl := AddOverlayButton(vert, pos, pad, sz, ResolveIcon(b["icon"]), SubStr(b["name"], 1, 1))
        ctl.OnEvent("Click", SendChat.Bind(b["command"]))
        HoverTips[ctl.Hwnd] := b["name"] "  (" b["command"] ")"
        pos += sz + gap
    }
    cog := AddOverlayButton(vert, pos, pad, sz, ICON_DIR "\cog.png", "*")
    cog.OnEvent("Click", (*) => ShowSettings())
    HoverTips[cog.Hwnd] := "Settings"

    UpdateVisibility()
}

AddOverlayButton(vert, pos, pad, sz, iconPath, fallbackText) {
    opt := (vert ? "x" pad " y" pos : "x" pos " y" pad) " w" sz " h" sz
    if FileExist(iconPath)
        return OvGui.AddPicture(opt " BackgroundTrans", iconPath)
    return OvGui.AddText(opt " +0x100 +0x200 Center cD8D8D8 Background333333", fallbackText)
}

UpdateVisibility() {
    global OvShown
    if !OvGui
        return
    want := IsPoeActive() || WinActive("ahk_id " OvGui.Hwnd)
        || (SettingsGui && WinActive("ahk_id " SettingsGui.Hwnd))
    if want && !OvShown {
        x := Max(0, Min(Settings["x"], A_ScreenWidth - 40))
        y := Max(0, Min(Settings["y"], A_ScreenHeight - 40))
        OvGui.Show("NA x" x " y" y " w" OvW " h" OvH)
        OvShown := true
    } else if !want && OvShown {
        OvGui.Hide()
        ToolTip()
        OvShown := false
    }
}

OnGripDown(wParam, lParam, msg, hwnd) {
    if OvGui && hwnd = OvGrip
        PostMessage(0xA1, 2, , , "ahk_id " OvGui.Hwnd)   ; WM_NCLBUTTONDOWN, HTCAPTION -> drag
}

OnDragEnd(wParam, lParam, msg, hwnd) {
    if OvGui && hwnd = OvGui.Hwnd {
        WinGetPos(&x, &y, , , "ahk_id " OvGui.Hwnd)
        Settings["x"] := x
        Settings["y"] := y
        SaveConfig()
    }
}

OnOverlayHover(wParam, lParam, msg, hwnd) {
    global LastTipHwnd
    if !OvGui || !OvShown
        return
    MouseGetPos(, , , &h, 2)
    if h = LastTipHwnd
        return
    LastTipHwnd := h
    if HoverTips.Has(h)
        ToolTip(HoverTips[h])
    else
        ToolTip()
}

OnMessage(0x201, OnGripDown)      ; WM_LBUTTONDOWN
OnMessage(0x232, OnDragEnd)       ; WM_EXITSIZEMOVE
OnMessage(0x200, OnOverlayHover)  ; WM_MOUSEMOVE
