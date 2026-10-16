; Hover effect for the travel buttons and the widgets button: while the pointer is on one, its own icon is drawn
; brightened on top of itself, with a faint glow in the icon's main colour around it. It lives in its own
; click-through layered window (per-pixel alpha), so it never takes the mouse or focus from the button underneath.
; Buttons without an icon image get no effect.

global BtnHoverCtls := []        ; [control, icon path] per button (rebuilt with the overlay)
global BtnHoverGui := ""
global BtnHoverOn := false
global BtnHoverSize := 0, BtnHoverKey := ""   ; side of the cached bitmap (button + glow), and its icon|size key
global BtnHoverDC := 0, BtnHoverBmp := 0, BtnHoverOld := 0
global BtnHoverImgs := Map()     ; icon path -> GDI+ image (0 = could not be loaded)
global BtnGlowColors := Map()    ; icon path -> 0xRRGGBB
global GdipToken := 0
global BTN_HOVER_GAIN := 1.4     ; colour multiplier
global BTN_HOVER_LIFT := 0.06    ; colour offset, so dark icons brighten too
global BTN_GLOW_R := 10          ; px the glow reaches past the button
global BTN_GLOW_ALPHA := 0.40    ; opacity of the glow at the icon's edge
global BTN_GLOW_FALLBACK := 0xC8AA6E   ; glow for icons without a clear main colour (the widgets' gold)

; Starts GDI+ and loads the icon (once per file). Returns the image, or 0 when it can't be loaded.
BtnHoverImage(path) {
    global GdipToken
    if BtnHoverImgs.Has(path)
        return BtnHoverImgs[path]
    if !FileExist(path)
        return 0
    if !GdipToken {
        DllCall("LoadLibrary", "Str", "gdiplus")
        si := Buffer(24, 0), NumPut("UInt", 1, si)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
        GdipToken := tok
    }
    if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &img := 0)
        img := 0
    BtnHoverImgs[path] := img
    return img
}

; The icon's main colour as 0xRRGGBB: the average of its opaque pixels, weighted towards saturated ones so the dark
; rim and background don't dull it, then brightened and made a little more vivid so it reads as a glow.
BtnGlowColor(path, img) {
    if BtnGlowColors.Has(path)
        return BtnGlowColors[path]
    n := 16
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", n, "Int", n, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bm := 0)   ; 32bpp ARGB
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bm, "Ptr*", &gfx := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gfx, "Int", 7)
    DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gfx, "Ptr", img, "Int", 0, "Int", 0, "Int", n, "Int", n)
    r := g := b := wsum := 0
    Loop n * n {
        DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", bm, "Int", Mod(A_Index - 1, n), "Int", (A_Index - 1) // n, "UInt*", &px := 0)
        a := (px >> 24) & 0xFF
        pr := (px >> 16) & 0xFF, pg := (px >> 8) & 0xFF, pb := px & 0xFF
        hi := Max(pr, pg, pb)
        sat := hi ? (hi - Min(pr, pg, pb)) / hi : 0
        wt := (a / 255) * sat * sat * (hi / 255 + 0.2)
        r += pr * wt, g += pg * wt, b += pb * wt, wsum += wt
    }
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bm)
    col := BTN_GLOW_FALLBACK
    if wsum > 0.5 {
        r /= wsum, g /= wsum, b /= wsum
        hi := Max(r, g, b)
        if hi > 0 {
            k := 255 / hi                    ; full brightness
            r *= k, g *= k, b *= k
            mid := (r + g + b) / 3           ; and a little more colour
            r := Min(255, Max(0, mid + (r - mid) * 1.25))
            g := Min(255, Max(0, mid + (g - mid) * 1.25))
            b := Min(255, Max(0, mid + (b - mid) * 1.25))
            col := (Round(r) << 16) | (Round(g) << 8) | Round(b)
        }
    }
    BtnGlowColors[path] := col
    return col
}

; Renders the glow and the brightened icon into a (sz + 2 * glow radius) square 32-bit bitmap. GDI+ draws straight
; into the DIB's memory as a premultiplied-alpha bitmap, which is what layered windows expect.
BtnHoverRender(img, sz, path) {
    global BtnHoverDC, BtnHoverBmp, BtnHoverOld, BtnHoverSize
    BtnHoverFree()
    m := BTN_GLOW_R
    tot := sz + 2 * m
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    bi := Buffer(40, 0)
    NumPut("UInt", 40, "Int", tot, "Int", -tot, "UShort", 1, "UShort", 32, bi)   ; top-down 32 bpp
    bmp := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
    BtnHoverOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", bmp, "Ptr")
    BtnHoverDC := hdc, BtnHoverBmp := bmp, BtnHoverSize := tot

    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", tot, "Int", tot, "Int", tot * 4, "Int", 0xE200B, "Ptr", bits, "Ptr*", &pb := 0)   ; 32bpp PARGB
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pb, "Ptr*", &gfx := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gfx, "Int", 4)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gfx, "Int", 7)   ; high quality bicubic

    if m > 0 {
        ; glow: a round gradient, strongest at the icon's edge and fading to nothing at the window's edge
        col := BtnGlowColor(path, img) & 0xFFFFFF
        DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &gp := 0)
        DllCall("gdiplus\GdipAddPathEllipseI", "Ptr", gp, "Int", 0, "Int", 0, "Int", tot, "Int", tot)
        DllCall("gdiplus\GdipCreatePathGradientFromPath", "Ptr", gp, "Ptr*", &br := 0)
        tIcon := 2 * m / tot                  ; gradient position of the icon's edge (0 = window edge, 1 = centre)
        cols := Buffer(16), pos := Buffer(16)
        for i, spec in [[0, 0], [tIcon * 0.5, BTN_GLOW_ALPHA * 0.2], [tIcon, BTN_GLOW_ALPHA], [1, BTN_GLOW_ALPHA]] {
            NumPut("Float", spec[1], pos, (i - 1) * 4)
            NumPut("UInt", (Round(spec[2] * 255) << 24) | col, cols, (i - 1) * 4)
        }
        DllCall("gdiplus\GdipSetPathGradientPresetBlend", "Ptr", br, "Ptr", cols, "Ptr", pos, "Int", 4)
        DllCall("gdiplus\GdipFillEllipseI", "Ptr", gfx, "Ptr", br, "Int", 0, "Int", 0, "Int", tot, "Int", tot)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
        DllCall("gdiplus\GdipDeletePath", "Ptr", gp)
    }

    DllCall("gdiplus\GdipGetImageWidth", "Ptr", img, "UInt*", &iw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", img, "UInt*", &ih := 0)
    mx := Buffer(100, 0)                      ; 5x5 colour matrix: R, G, B scaled and lifted, alpha untouched
    Loop 3
        NumPut("Float", BTN_HOVER_GAIN, mx, (A_Index - 1) * 24)
    NumPut("Float", 1, mx, 3 * 24)
    NumPut("Float", 1, mx, 4 * 24)
    Loop 3
        NumPut("Float", BTN_HOVER_LIFT, mx, 4 * 20 + (A_Index - 1) * 4)
    DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &attr := 0)
    DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "Ptr", attr, "Int", 1, "Int", 1, "Ptr", mx, "Ptr", 0, "Int", 0)
    DllCall("gdiplus\GdipSetImageAttributesWrapMode", "Ptr", attr, "Int", 3, "UInt", 0, "Int", 0)   ; clamp: no edge bleed
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", gfx, "Ptr", img, "Int", m, "Int", m, "Int", sz, "Int", sz
        , "Int", 0, "Int", 0, "Int", iw, "Int", ih, "Int", 2, "Ptr", attr, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", attr)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pb)
}

BtnHoverFree() {
    global BtnHoverDC, BtnHoverBmp, BtnHoverOld, BtnHoverSize, BtnHoverKey
    if BtnHoverDC {
        DllCall("SelectObject", "Ptr", BtnHoverDC, "Ptr", BtnHoverOld)
        DllCall("DeleteObject", "Ptr", BtnHoverBmp)
        DllCall("DeleteDC", "Ptr", BtnHoverDC)
    }
    BtnHoverDC := 0, BtnHoverBmp := 0, BtnHoverSize := 0, BtnHoverKey := ""
}

; Draws the glow and the brightened icon over the screen rectangle (x, y, sz, sz) of a button.
BtnHoverShow(path, x, y, sz) {
    global BtnHoverGui, BtnHoverOn, BtnHoverKey
    img := BtnHoverImage(path)
    if !img {
        BtnHoverHide()
        return
    }
    if !BtnHoverGui {
        ; +E0x80000 layered, +E0x20 click-through, +E0x08000000 never activates
        BtnHoverGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x80000 +E0x20 +E0x08000000")
        NoFade(BtnHoverGui)
    }
    if BtnHoverKey != path "|" sz {
        BtnHoverRender(img, sz, path)
        BtnHoverKey := path "|" sz
    }
    tot := BtnHoverSize, x -= BTN_GLOW_R, y -= BTN_GLOW_R   ; the glow reaches past the button on every side
    BtnHoverGui.Show("NA x" x " y" y " w" tot " h" tot)
    pt := Buffer(8), NumPut("Int", x, "Int", y, pt)
    size := Buffer(8), NumPut("Int", tot, "Int", tot, size)
    src := Buffer(8, 0)
    blend := Buffer(4, 0), NumPut("UChar", 0, "UChar", 0, "UChar", 255, "UChar", 1, blend)   ; AC_SRC_OVER, alpha 255, AC_SRC_ALPHA
    DllCall("UpdateLayeredWindow", "Ptr", BtnHoverGui.Hwnd, "Ptr", 0, "Ptr", pt, "Ptr", size
        , "Ptr", BtnHoverDC, "Ptr", src, "UInt", 0, "Ptr", blend, "UInt", 2)
    ; stay above the overlay window (both are topmost)
    DllCall("SetWindowPos", "Ptr", BtnHoverGui.Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    BtnHoverOn := true
}

BtnHoverHide() {
    global BtnHoverOn
    if BtnHoverOn && BtnHoverGui
        BtnHoverGui.Hide()
    BtnHoverOn := false
}

; Polled like the other hover effects: the pointer position against each button's screen rectangle
; (the overlay's keyed-out background doesn't get mouse messages).
UpdateBtnHover() {
    found := false
    if OvGui && OvShown && BtnHoverCtls.Length && !GetKeyState("LButton", "P") {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        try {
            WinGetPos(&wx, &wy, , , "ahk_id " OvGui.Hwnd)
            for e in BtnHoverCtls {
                e[1].GetPos(&cx, &cy, &cw, &ch)
                if mx >= wx + cx && mx < wx + cx + cw && my >= wy + cy && my < wy + cy + ch {
                    found := true
                    BtnHoverShow(e[2], wx + cx, wy + cy, cw)
                    break
                }
            }
        }
    }
    if !found
        BtnHoverHide()
}
SetTimer(UpdateBtnHover, 30)
