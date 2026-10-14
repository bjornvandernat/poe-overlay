; Floating button bar, shown only while PoE (or our own settings window) has focus

global OvGui := ""
global OvGrip := 0
global OvHandle := Map()   ; hwnds of the resize handle bars
global OvShown := false
global OvW := 0
global OvH := 0
global HoverTips := Map()
global LastTipHwnd := 0
global TipShown := false
global HoverSince := 0
global TOOLTIP_DELAY := 500    ; ms the pointer must rest on a control before its tooltip appears
global OvChrome := []       ; grip + resize handle bars: shown on hover unless locked
global OvCog := ""          ; settings cog: shown on hover, also when locked
global OvHover := false
global OvDragging := false  ; keeps the chrome visible during move/resize
global OV_BG := "1C1C1C"    ; background colour; made click-through + invisible when not hovering

BuildOverlay() {
    global OvGui, OvGrip, OvHandle, OvChrome, OvCog, OvShown, OvW, OvH, HoverTips
    old := OvGui
    HoverTips := Map()
    OvChrome := []

    ; Only the button images scale. Padding, grip and resize handle keep a fixed thickness; the
    ; cog stays at its base size and is centred on the cross axis.
    sz := Max(8, Round(BUTTON_SIZE * Settings["scale"] / 100))
    cogSz := COG_SIZE
    pad := 3, gap := 3, grip := 8, handle := 10, t := 3
    vert := Settings["vertical"]
    n := EnabledCount()
    along := pad + grip + pad + n * (sz + gap) + cogSz + pad + handle
    cross := Max(sz, cogSz) + 2 * pad
    OvW := vert ? cross : along
    OvH := vert ? along : cross

    ; -DPIScale: sizes and positions are real pixels; +E0x08000000 = never take focus on click
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
    g.BackColor := OV_BG
    g.MarginX := 0, g.MarginY := 0

    OvGrip := g.AddText(vert ? "x0 y0 w" cross " h" grip " +0x100 Background3A3A3A"
                             : "x0 y0 w" grip " h" cross " +0x100 Background3A3A3A").Hwnd
    OvChrome.Push(GuiCtrlFromHwnd(OvGrip))
    HoverTips[OvGrip] := "Drag to move"

    pos := pad + grip + pad
    for b in Buttons {
        if !b["enabled"]
            continue
        ctl := AddOverlayButton(g, vert, pos, (cross - sz) // 2, sz, ResolveIcon(b["icon"]), SubStr(b["name"], 1, 1))
        ctl.OnEvent("Click", SendChat.Bind(b["command"]))
        HoverTips[ctl.Hwnd] := b["name"] "  (" b["command"] ")"
        pos += sz + gap
    }
    cog := AddOverlayButton(g, vert, pos, (cross - cogSz) // 2, cogSz, ICON_DIR "\cog.png", "*")
    cog.OnEvent("Click", (*) => ShowSettings())
    OvCog := cog
    HoverTips[cog.Hwnd] := "Settings"

    ; resize handle: a corner edge (bottom + right bars, like a "┘") in the bottom-right corner
    OvHandle := Map()
    for spec in [[OvW - t, OvH - handle, t, handle], [OvW - handle, OvH - t, handle, t]] {
        bar := g.AddText("x" spec[1] " y" spec[2] " w" spec[3] " h" spec[4] " +0x100 Background8A8A8A")
        OvHandle[bar.Hwnd] := true
        OvChrome.Push(bar)
        HoverTips[bar.Hwnd] := "Drag to resize (" Settings["scale"] "%)"
    }

    ; swap in the new window before destroying the old one so resizing doesn't flicker
    OvGui := g
    ApplyChrome()
    if OvShown
        ShowOverlay()
    if old
        old.Destroy()
    UpdateVisibility()
}

AddOverlayButton(g, vert, pos, crossPos, sz, iconPath, fallbackText) {
    opt := (vert ? "x" crossPos " y" pos : "x" pos " y" crossPos) " w" sz " h" sz
    if FileExist(iconPath)
        return g.AddPicture(opt " BackgroundTrans", iconPath)
    return g.AddText(opt " +0x100 +0x200 Center cD8D8D8 Background333333", fallbackText)
}

ShowOverlay() {
    x := Max(0, Min(Settings["x"], A_ScreenWidth - 40))
    y := Max(0, Min(Settings["y"], A_ScreenHeight - 40))
    OvGui.Show("NA x" x " y" y " w" OvW " h" OvH)
    ApplyChrome()
}

; Not hovering: only the button images are visible (background keyed out and click-through; grip,
; cog and resize handle hidden). Hovering: the cog appears, plus the background, grip and resize
; handle unless the overlay is locked.
ApplyChrome() {
    full := OvHover && !Settings["locked"]
    for ctl in OvChrome
        ctl.Visible := full
    OvCog.Visible := OvHover
    try WinSetTransColor(full ? "Off" : OV_BG, "ahk_id " OvGui.Hwnd)   ; throws while hidden
}

; Hover is decided by the cursor position over the window rectangle, because the keyed-out
; background does not receive mouse messages.
UpdateHover() {
    global OvHover, OvDragging
    on := false
    if OvGui && OvShown {
        if OvDragging && !GetKeyState("LButton", "P")
            OvDragging := false
        if OvDragging
            on := true
        else {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my)
            WinGetPos(&x, &y, &w, &h, "ahk_id " OvGui.Hwnd)
            on := mx >= x && mx < x + w && my >= y && my < y + h
        }
    }
    if on != OvHover {
        OvHover := on
        ApplyChrome()
    }
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
    global OvDragging
    if !OvGui
        return
    if Settings["locked"]
        return
    if hwnd = OvGrip {
        OvDragging := true
        PostMessage(0xA1, 2, , , "ahk_id " OvGui.Hwnd)   ; WM_NCLBUTTONDOWN, HTCAPTION -> drag
    } else if OvHandle.Has(hwnd)
        SetTimer(ResizeDrag, -1)                          ; run outside the message handler
}

; The diagonal mouse movement since the press decides the new scale. Only the images grow, so
; width + height change by (images along the bar, plus one on the cross axis once scale >= 100)
; times the image size, per scale percent; that keeps the corner handle under the cursor.
ResizeDrag() {
    global OvDragging
    OvDragging := true
    CoordMode("Mouse", "Screen")
    ToolTip()
    MouseGetPos(&mx0, &my0)
    start := built := s := Settings["scale"]
    pxPerPercent := BUTTON_SIZE / 100 * Max(1, EnabledCount() + (start >= 100 ? 1 : 0))
    while GetKeyState("LButton", "P") {
        MouseGetPos(&mx, &my)
        s := Max(SCALE_MIN, Min(SCALE_MAX, Round(start + ((mx - mx0) + (my - my0)) / pxPerPercent)))
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
    OvDragging := false
    SaveConfig()
}

OnOverlayCursor(wParam, lParam, msg, hwnd) {
    if OvGui && OvHandle.Has(wParam) {
        DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32642, "Ptr"))   ; IDC_SIZENWSE
        return true
    }
}

OnDragEnd(wParam, lParam, msg, hwnd) {
    global OvDragging
    if OvGui && hwnd = OvGui.Hwnd {
        WinGetPos(&x, &y, , , "ahk_id " OvGui.Hwnd)
        Settings["x"] := x
        Settings["y"] := y
        SaveConfig()
        OvDragging := false
    }
}

; Polled instead of driven by WM_MOUSEMOVE: that message stops arriving while the mouse is
; pressed (drag/resize), when it leaves the overlay, or when the overlay hides.
UpdateTooltip() {
    global LastTipHwnd, TipShown, HoverSince
    h := 0
    if OvGui && OvShown && !GetKeyState("LButton", "P") {
        MouseGetPos(, , &win, &h, 2)
        if win != OvGui.Hwnd || !HoverTips.Has(h)
            h := 0
    }
    if h != LastTipHwnd {
        LastTipHwnd := h
        HoverSince := A_TickCount
        if TipShown {
            ToolTip()
            TipShown := false
        }
    }
    if h && !TipShown && A_TickCount - HoverSince >= TOOLTIP_DELAY {
        ToolTip(HoverTips[h])
        TipShown := true
    }
}

OnMessage(0x201, OnOverlayDown)    ; WM_LBUTTONDOWN
OnMessage(0x232, OnDragEnd)        ; WM_EXITSIZEMOVE
SetTimer(UpdateHover, 50)
SetTimer(UpdateTooltip, 50)
OnMessage(0x20, OnOverlayCursor)   ; WM_SETCURSOR
