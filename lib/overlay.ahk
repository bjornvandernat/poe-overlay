; Floating button bar, shown only while PoE (or our own settings window) has focus

global OvGui := ""
global OvGrip := 0
global OvHandle := Map()   ; hwnds of the resize handle bars
global OvShown := false
global OvW := 0
global OvH := 0
global HoverTips := Map()
global LastTipHwnd := 0

BuildOverlay() {
    global OvGui, OvGrip, OvHandle, OvShown, OvW, OvH, HoverTips
    old := OvGui
    HoverTips := Map()

    ; every dimension scales uniformly with the stored scale percentage
    s := Settings["scale"] / 100
    sz := Max(8, Round(Settings["size"] * s))
    pad := Max(1, Round(3 * s)), gap := pad
    grip := Max(4, Round(8 * s))
    handle := Max(6, Round(10 * s))
    vert := Settings["vertical"]
    count := Buttons.Length + 1   ; + cog
    along := pad + grip + pad + count * (sz + gap) - gap + pad + handle
    cross := sz + 2 * pad
    OvW := vert ? cross : along
    OvH := vert ? along : cross

    ; -DPIScale: sizes and positions are real pixels; +E0x08000000 = never take focus on click
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
    g.BackColor := "1C1C1C"
    g.MarginX := 0, g.MarginY := 0

    OvGrip := g.AddText(vert ? "x0 y0 w" cross " h" grip " +0x100 Background3A3A3A"
                             : "x0 y0 w" grip " h" cross " +0x100 Background3A3A3A").Hwnd
    HoverTips[OvGrip] := "Drag to move"

    pos := pad + grip + pad
    for b in Buttons {
        ctl := AddOverlayButton(g, vert, pos, pad, sz, ResolveIcon(b["icon"]), SubStr(b["name"], 1, 1))
        ctl.OnEvent("Click", SendChat.Bind(b["command"]))
        HoverTips[ctl.Hwnd] := b["name"] "  (" b["command"] ")"
        pos += sz + gap
    }
    cog := AddOverlayButton(g, vert, pos, pad, sz, ICON_DIR "\cog.png", "*")
    cog.OnEvent("Click", (*) => ShowSettings())
    HoverTips[cog.Hwnd] := "Settings"

    ; resize handle: a corner edge (bottom + right bars, like a "┘") in the bottom-right corner
    t := Max(2, Round(3 * s))
    OvHandle := Map()
    for spec in [[OvW - t, OvH - handle, t, handle], [OvW - handle, OvH - t, handle, t]] {
        bar := g.AddText("x" spec[1] " y" spec[2] " w" spec[3] " h" spec[4] " +0x100 Background8A8A8A")
        OvHandle[bar.Hwnd] := true
        HoverTips[bar.Hwnd] := "Drag to resize (" Settings["scale"] "%)"
    }

    ; swap in the new window before destroying the old one so resizing doesn't flicker
    OvGui := g
    if OvShown
        ShowOverlay()
    if old
        old.Destroy()
    UpdateVisibility()
}

AddOverlayButton(g, vert, pos, pad, sz, iconPath, fallbackText) {
    opt := (vert ? "x" pad " y" pos : "x" pos " y" pad) " w" sz " h" sz
    if FileExist(iconPath)
        return g.AddPicture(opt " BackgroundTrans", iconPath)
    return g.AddText(opt " +0x100 +0x200 Center cD8D8D8 Background333333", fallbackText)
}

ShowOverlay() {
    x := Max(0, Min(Settings["x"], A_ScreenWidth - 40))
    y := Max(0, Min(Settings["y"], A_ScreenHeight - 40))
    OvGui.Show("NA x" x " y" y " w" OvW " h" OvH)
}

UpdateVisibility() {
    global OvShown
    if !OvGui
        return
    want := IsPoeActive() || WinActive("ahk_id " OvGui.Hwnd)
        || (SettingsGui && WinActive("ahk_id " SettingsGui.Hwnd))
    if want && !OvShown {
        ShowOverlay()
        OvShown := true
    } else if !want && OvShown {
        OvGui.Hide()
        ToolTip()
        OvShown := false
    }
}

OnOverlayDown(wParam, lParam, msg, hwnd) {
    if !OvGui
        return
    if hwnd = OvGrip
        PostMessage(0xA1, 2, , , "ahk_id " OvGui.Hwnd)   ; WM_NCLBUTTONDOWN, HTCAPTION -> drag
    else if OvHandle.Has(hwnd)
        SetTimer(ResizeDrag, -1)                          ; run outside the message handler
}

; Uniform scaling: the diagonal mouse movement since the press decides the new scale.
ResizeDrag() {
    CoordMode("Mouse", "Screen")
    ToolTip()
    WinGetPos(, , &w0, &h0, "ahk_id " OvGui.Hwnd)
    MouseGetPos(&mx0, &my0)
    start := built := s := Settings["scale"]
    while GetKeyState("LButton", "P") {
        MouseGetPos(&mx, &my)
        ratio := (w0 + h0 + (mx - mx0) + (my - my0)) / (w0 + h0)
        s := Max(SCALE_MIN, Min(SCALE_MAX, Round(start * ratio)))
        if Abs(s - built) >= 2 {
            built := Settings["scale"] := s
            BuildOverlay()
        }
        Sleep(15)
    }
    if s != built {
        Settings["scale"] := s
        BuildOverlay()
    }
    SaveConfig()
}

OnOverlayCursor(wParam, lParam, msg, hwnd) {
    if OvGui && OvHandle.Has(wParam) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32642, "Ptr"))   ; IDC_SIZENWSE
        return true
    }
}

OnDragEnd(wParam, lParam, msg, hwnd) {
    if OvGui && hwnd = OvGui.Hwnd {
        WinGetPos(&x, &y, , , "ahk_id " OvGui.Hwnd)
        Settings["x"] := x
        Settings["y"] := y
        SaveConfig()
    }
}

; Polled instead of driven by WM_MOUSEMOVE: that message stops arriving while the mouse is
; pressed (drag/resize), when it leaves the overlay, or when the overlay hides.
UpdateTooltip() {
    global LastTipHwnd
    h := 0
    if OvGui && OvShown && !GetKeyState("LButton", "P") {
        MouseGetPos(, , &win, &h, 2)
        if win != OvGui.Hwnd || !HoverTips.Has(h)
            h := 0
    }
    if h = LastTipHwnd
        return
    LastTipHwnd := h
    if h
        ToolTip(HoverTips[h])
    else
        ToolTip()
}

OnMessage(0x201, OnOverlayDown)    ; WM_LBUTTONDOWN
OnMessage(0x232, OnDragEnd)        ; WM_EXITSIZEMOVE
SetTimer(UpdateTooltip, 50)
OnMessage(0x20, OnOverlayCursor)   ; WM_SETCURSOR
