; Custom tooltip: a small rounded window sized to its text that fades in next to the element it describes.
; ShowTip(text, controlHwnd, side) / HideTip(). The window never takes focus and is click-through, so it can't
; interfere with the element underneath.

global TipGui := ""
global TipStart := 0

global TIP_BG := "20242E"       ; same dark blue as the widgets' "+ Add search" row
global TIP_BORDER := "2B3345"   ; the blue of the widget item rows
global TIP_FG := "E8E8E8"
global TIP_FG_DIM := "9AA3B5"   ; the detail text after a bold title
global TIP_FONT_PX := 13
global TIP_PAD_X := 10
global TIP_PAD_Y := 6
global TIP_MAX_W := 320         ; longer text wraps
global TIP_GAP := 8             ; distance from the element
global TIP_SUB_GAP := 6         ; between the bold title and the detail text
global TIP_RADIUS := 12         ; corner diameter for the Windows 10 fallback
global TIP_FADE_MS := 120

; text is a string (shown bold), or [bold title, dim detail]. With an empty title, [ "", detail ] shows just the
; dim, normal-weight detail.
; side: "above", "below", "left" or "right" of the element; flips to the opposite side when it doesn't fit.
ShowTip(text, hwnd, side := "above") {
    global TipGui, TipStart
    HideTip()
    main := IsObject(text) ? text[1] : text
    sub := IsObject(text) ? text[2] : ""
    if main = "" && sub = ""
        return
    size := MeasureTip(main, sub)
    W := size[1] + 2 * TIP_PAD_X
    H := size[2] + 2 * TIP_PAD_Y

    rc := Buffer(16)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)   ; the element, in screen pixels
    l := NumGet(rc, 0, "Int"), t := NumGet(rc, 4, "Int"), r := NumGet(rc, 8, "Int"), b := NumGet(rc, 12, "Int")
    MonitorBounds((l + r) // 2, (t + b) // 2, &ml, &mt, &mr, &mb)
    pos := TipPosition(side, l, t, r, b, W, H, ml, mt, mr, mb)

    ; no-activate + click-through + layered (needed for the fade)
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08080020")
    g.BackColor := TIP_BG
    g.MarginX := 0, g.MarginY := 0
    g.SetFont("s" Round(TIP_FONT_PX * 72 / A_ScreenDPI, 1) " bold c" TIP_FG, "Segoe UI")
    if main != ""
        g.AddText("x" TIP_PAD_X " y" TIP_PAD_Y " w" size[3] " h" size[2] " +0x80", main)   ; +0x80: show "&" literally
    if sub != "" {
        g.SetFont("norm c" TIP_FG_DIM)
        g.AddText("x" (TIP_PAD_X + (main != "" ? size[3] + TIP_SUB_GAP : 0)) " y" TIP_PAD_Y " w" size[4] " h" size[2] " +0x80", sub)
    }

    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 3, "Int*", 1, "UInt", 4)   ; no Windows fade, we fade ourselves
    ; Windows 11: rounded corners and a border colour from DWM. Otherwise a rounded region (without a border).
    hr := DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 33, "Int*", 2, "UInt", 4)   ; DWMWCP_ROUND
    border := (Integer("0x" SubStr(TIP_BORDER, 1, 2))) | (Integer("0x" SubStr(TIP_BORDER, 3, 2)) << 8) | (Integer("0x" SubStr(TIP_BORDER, 5, 2)) << 16)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 34, "UInt*", border, "UInt", 4)   ; DWMWA_BORDER_COLOR
    if hr != 0 {
        rgn := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", W + 1, "Int", H + 1, "Int", TIP_RADIUS, "Int", TIP_RADIUS, "Ptr")
        DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", rgn, "Int", true)
    }

    TipGui := g
    SetTipAlpha(g, 0)   ; invisible until it has been placed
    g.Show("NA x" pos[1] " y" pos[2] " w" W " h" H)
    TipStart := A_TickCount
    SetTimer(TipFadeStep, 15)
}

; Window opacity 0-255 (set on the handle, so it also works before the window is shown).
SetTipAlpha(g, alpha) {
    DllCall("SetLayeredWindowAttributes", "Ptr", g.Hwnd, "UInt", 0, "UChar", alpha, "UInt", 2)   ; LWA_ALPHA
}

HideTip() {
    global TipGui
    SetTimer(TipFadeStep, 0)
    g := TipGui
    if !g
        return
    TipGui := ""   ; clear first, then destroy
    g.Destroy()
}

TipFadeStep() {
    if !TipGui {
        SetTimer(TipFadeStep, 0)
        return
    }
    a := Min(255, Round((A_TickCount - TipStart) / TIP_FADE_MS * 255))
    SetTipAlpha(TipGui, a)
    if a >= 255
        SetTimer(TipFadeStep, 0)
}

; Text size in pixels as [width, height, title width, detail width]. The title is bold and the detail normal
; weight, side by side on one line. A lone title or a lone detail is its natural width, or TIP_MAX_W wide when
; that is too long (then it wraps).
MeasureTip(main, sub := "") {
    g := Gui("-DPIScale")
    g.SetFont("s" Round(TIP_FONT_PX * 72 / A_ScreenDPI, 1) " bold", "Segoe UI")
    mw := mh := sw := sh := 0
    if main != "" {
        g.AddText("+0x80", main).GetPos(, , &mw, &mh)
        if sub = "" && mw > TIP_MAX_W
            g.AddText("w" TIP_MAX_W " +0x80", main).GetPos(, , &mw, &mh)
    }
    if sub != "" {
        g.SetFont("norm")
        g.AddText("+0x80", sub).GetPos(, , &sw, &sh)
        if main = "" && sw > TIP_MAX_W
            g.AddText("w" TIP_MAX_W " +0x80", sub).GetPos(, , &sw, &sh)
    }
    g.Destroy()
    both := main != "" && sub != ""
    return [mw + (both ? TIP_SUB_GAP : 0) + sw, Max(mh, sh), mw, sw]
}

; Bounds of the monitor containing the point.
MonitorBounds(x, y, &l, &t, &r, &b) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if x >= l && x < r && y >= t && y < b
            return
    }
    MonitorGet(MonitorGetPrimary(), &l, &t, &r, &b)
}

; Top-left of the tooltip: centred on the chosen side of the element, flipped to the opposite side if it
; would leave the monitor on that axis, and finally kept inside the monitor.
TipPosition(side, l, t, r, b, W, H, ml, mt, mr, mb) {
    cx := (l + r) // 2, cy := (t + b) // 2
    Loop 2 {
        switch side {
            case "above": x := cx - W // 2, y := t - TIP_GAP - H
            case "below": x := cx - W // 2, y := b + TIP_GAP
            case "left":  x := l - TIP_GAP - W, y := cy - H // 2
            default:      x := r + TIP_GAP, y := cy - H // 2   ; "right"
        }
        out := (side = "above" && y < mt) || (side = "below" && y + H > mb)
            || (side = "left" && x < ml) || (side != "above" && side != "below" && side != "left" && x + W > mr)
        if !out || A_Index = 2
            break
        side := side = "above" ? "below" : side = "below" ? "above" : side = "left" ? "right" : "left"
    }
    return [Max(ml, Min(x, mr - W)), Max(mt, Min(y, mb - H))]
}
