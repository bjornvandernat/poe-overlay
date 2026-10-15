; Hover effect for the travel buttons and the widgets button: while the pointer is on one, its own icon is drawn
; brightened on top of itself. It lives in its own click-through layered window (per-pixel alpha), so it never
; takes the mouse or focus from the button underneath. Buttons without an icon image get no effect.

global BtnHoverCtls := []        ; [control, icon path] per button (rebuilt with the overlay)
global BtnHoverGui := ""
global BtnHoverOn := false
global BtnHoverSize := 0, BtnHoverKey := ""   ; size and icon of the cached bitmap
global BtnHoverDC := 0, BtnHoverBmp := 0, BtnHoverOld := 0
global BtnHoverImgs := Map()     ; icon path -> GDI+ image (0 = could not be loaded)
global GdipToken := 0
global BTN_HOVER_GAIN := 1.4     ; colour multiplier
global BTN_HOVER_LIFT := 0.06    ; colour offset, so dark icons brighten too

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

; Renders the icon at sz x sz, brightened, into a 32-bit bitmap (as layered windows expect).
BtnHoverRender(img, sz) {
    global BtnHoverDC, BtnHoverBmp, BtnHoverOld, BtnHoverSize
    BtnHoverFree()
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    bi := Buffer(40, 0)
    NumPut("UInt", 40, "Int", sz, "Int", -sz, "UShort", 1, "UShort", 32, bi)   ; top-down 32 bpp
    bmp := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
    BtnHoverOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", bmp, "Ptr")
    BtnHoverDC := hdc, BtnHoverBmp := bmp, BtnHoverSize := sz

    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &gfx := 0)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gfx, "Int", 7)   ; high quality bicubic
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", img, "UInt*", &iw := 0)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", img, "UInt*", &ih := 0)
    m := Buffer(100, 0)                       ; 5x5 colour matrix: R, G, B scaled and lifted, alpha untouched
    Loop 3
        NumPut("Float", BTN_HOVER_GAIN, m, (A_Index - 1) * 24)
    NumPut("Float", 1, m, 3 * 24)
    NumPut("Float", 1, m, 4 * 24)
    Loop 3
        NumPut("Float", BTN_HOVER_LIFT, m, 4 * 20 + (A_Index - 1) * 4)
    DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &attr := 0)
    DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "Ptr", attr, "Int", 1, "Int", 1, "Ptr", m, "Ptr", 0, "Int", 0)
    DllCall("gdiplus\GdipSetImageAttributesWrapMode", "Ptr", attr, "Int", 3, "UInt", 0, "Int", 0)   ; clamp: no edge bleed
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", gfx, "Ptr", img, "Int", 0, "Int", 0, "Int", sz, "Int", sz
        , "Int", 0, "Int", 0, "Int", iw, "Int", ih, "Int", 2, "Ptr", attr, "Ptr", 0, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", attr)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx)
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

; Draws the brightened icon over the screen rectangle (x, y, sz, sz).
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
        BtnHoverRender(img, sz)
        BtnHoverKey := path "|" sz
    }
    BtnHoverGui.Show("NA x" x " y" y " w" sz " h" sz)
    pt := Buffer(8), NumPut("Int", x, "Int", y, pt)
    size := Buffer(8), NumPut("Int", sz, "Int", sz, size)
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
