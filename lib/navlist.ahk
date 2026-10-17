; Page list of the settings window, drawn like the Windows 11 settings sidebars: an icon and a label per row, with a
; rounded highlight on the selected row and a fainter one under the pointer. It is a single bitmap control painted with
; GDI+; hover and clicks are worked out from the pointer position.

global NavCtl := "", NavBmp := 0, NavItems := [], NavSel := 1, NavHot := 0, NavOnSelect := ""
global NavW := 0, NavH := 0

; items: [[icon PNG path, label], ...]. onSelect(index) runs when a row is chosen.
NavCreate(g, x, y, w, items, onSelect) {
    global NavCtl, NavItems, NavSel, NavHot, NavOnSelect, NavW, NavH
    NavItems := items, NavSel := 1, NavHot := 0, NavOnSelect := onSelect
    NavW := w, NavH := Round(NavRowH() * items.Length + 4)
    NavCtl := g.AddText("x" x " y" y " w" w " h" NavH " +0xE +0x100")   ; SS_BITMAP | SS_NOTIFY
    NavCtl.OnEvent("Click", NavClick)
    NavRender()
    SetTimer(NavTick, 40)
}

NavRowH() => Round(34 * A_ScreenDPI / 96)

NavSelect(i) {
    global NavSel
    NavSel := i
    NavRender()
    if NavOnSelect
        NavOnSelect(i)
}

NavClick(*) {
    i := NavRowAt()
    if i
        NavSelect(i)
}

; Row under the pointer (0 = none), only while the pointer is over the list itself.
NavRowAt() {
    MouseGetPos(, , , &hwnd, 2)
    if !NavCtl || hwnd != NavCtl.Hwnd
        return 0
    pt := Buffer(8)
    DllCall("GetCursorPos", "Ptr", pt)
    DllCall("ScreenToClient", "Ptr", NavCtl.Hwnd, "Ptr", pt)
    y := NumGet(pt, 4, "Int") - 2
    i := y // NavRowH() + 1
    return (y >= 0 && i >= 1 && i <= NavItems.Length) ? i : 0
}

NavTick() {
    global NavHot
    if !SettingsGui {
        SetTimer(NavTick, 0)
        return
    }
    hot := NavRowAt()
    if hot != NavHot {
        NavHot := hot
        NavRender()
    }
}

; Called when the settings window closes.
NavFree() {
    global NavCtl, NavBmp
    SetTimer(NavTick, 0)
    NavCtl := ""
    if NavBmp {
        DllCall("DeleteObject", "Ptr", NavBmp)
        NavBmp := 0
    }
}

NavRender() {
    global NavBmp, GdipToken
    if !NavCtl
        return
    if !GdipToken {
        DllCall("LoadLibrary", "Str", "gdiplus")
        si := Buffer(24, 0), NumPut("UInt", 1, si)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
        GdipToken := tok
    }
    s := A_ScreenDPI / 96
    rowH := NavRowH()
    c := DllCall("GetSysColor", "Int", 15, "UInt")   ; COLOR_BTNFACE, the window background
    bg := 0xFF000000 | ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)

    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", NavW, "Int", NavH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bmp, "Ptr*", &gr := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", gr, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", gr, "Int", 5)   ; ClearType, fine on the opaque background
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", gr, "UInt", bg)

    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gr, "Int", 7)   ; high quality bicubic, for the scaled icons
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 4)
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &txtFam := 0)
    DllCall("gdiplus\GdipCreateFont", "Ptr", txtFam, "Float", 13 * s, "Int", 0, "Int", 2, "Ptr*", &txtFont := 0)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "Ptr*", &fmt := 0)
    DllCall("gdiplus\GdipSetStringFormatFlags", "Ptr", fmt, "Int", 0x1000)   ; no wrap
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)   ; centred vertically
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF1A1A1A, "Ptr*", &ink := 0)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0x16000000, "Ptr*", &selFill := 0)   ; 9 % black over the background
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0x0B000000, "Ptr*", &hotFill := 0)

    rc := Buffer(16)
    for i, it in NavItems {
        rx := 2 * s, ry := 2 + (i - 1) * rowH, rw := NavW - 4 * s, rh := rowH - 4
        if i = NavSel || i = NavHot {
            r := 5 * s, d := 2 * r
            DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", rx, "Float", ry, "Float", d, "Float", d, "Float", 180, "Float", 90)
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", rx + rw - d, "Float", ry, "Float", d, "Float", d, "Float", 270, "Float", 90)
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", rx + rw - d, "Float", ry + rh - d, "Float", d, "Float", d, "Float", 0, "Float", 90)
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", rx, "Float", ry + rh - d, "Float", d, "Float", d, "Float", 90, "Float", 90)
            DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
            DllCall("gdiplus\GdipFillPath", "Ptr", gr, "Ptr", (i = NavSel ? selFill : hotFill), "Ptr", path)
            DllCall("gdiplus\GdipDeletePath", "Ptr", path)
        }
        if FileExist(it[1]) && !DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", it[1], "Ptr*", &img := 0) {
            isz := Round(18 * s)
            DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gr, "Ptr", img, "Int", Round(rx + 10 * s), "Int", Round(ry + (rh - isz) / 2), "Int", isz, "Int", isz)
            DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
        }
        NumPut("Float", rx + 40 * s, "Float", ry, "Float", rw - 40 * s, "Float", rh, rc)
        DllCall("gdiplus\GdipDrawString", "Ptr", gr, "WStr", it[2], "Int", -1, "Ptr", txtFont, "Ptr", rc, "Ptr", fmt, "Ptr", ink)
    }

    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bmp, "Ptr*", &hbm := 0, "UInt", bg)
    old := SendMessage(0x172, 0, hbm, NavCtl)   ; STM_SETIMAGE, IMAGE_BITMAP
    if old
        DllCall("DeleteObject", "Ptr", old)
    NavBmp := hbm

    DllCall("gdiplus\GdipDeleteBrush", "Ptr", ink)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", selFill)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", hotFill)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    DllCall("gdiplus\GdipDeleteFont", "Ptr", txtFont)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", txtFam)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
}
