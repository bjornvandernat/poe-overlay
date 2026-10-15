; Stash search widgets: draggable panels of search items shown over the game.
; Clicking an item pastes its search string into PoE (Ctrl+F, Ctrl+V). While the widgets are open they
; are always editable (rename / delete / drag the title, right-click an item to edit it, "+ Add search",
; "+ New widget" in the toolbar). The built-in bar button (next to the cog) opens and closes them.

global WID_FILE := A_ScriptDir "\widgets.ini"
global Widgets := []         ; Map(name, x, y, items: [Map(name, search)]) + runtime keys: gui, w, h, hit, titleHwnd
global WidgetsOpen := false
global WdShown := false      ; currently visible (open, and PoE or one of our windows has focus)
global WdToolbar := ""
global WdDlg := ""           ; the one edit dialog that can be open

; Layout in real pixels (the windows are -DPIScale like the button bar)
global WD_FONT_PX := 13
global WD_TITLE_H := 28
global WD_ROW_H := 26
global WD_GAP := 3
global WD_MIN_W := 150
global WD_CTRL_W := 26       ; width of the rename / delete glyphs in the title bar
global TB_W := 440
global TB_H := 50

; ---- storage ----
; IniRead strips quotes around a whole value, which would mangle searches like "scarab", so every
; value is stored with a leading "|".

WEnc(s) {
    return "|" s
}

WDec(s) {
    return SubStr(s, 1, 1) = "|" ? SubStr(s, 2) : s
}

LoadWidgets() {
    global Widgets
    Widgets := []
    if !FileExist(WID_FILE)
        return
    Loop Integer(IniRead(WID_FILE, "General", "count", 0)) {
        sec := "Widget" A_Index
        w := Map("name", WDec(IniRead(WID_FILE, sec, "name", "|Widget"))
            , "x", Integer(IniRead(WID_FILE, sec, "x", 100))
            , "y", Integer(IniRead(WID_FILE, sec, "y", 100))
            , "items", [])
        Loop Integer(IniRead(WID_FILE, sec, "count", 0)) {
            isec := sec "Item" A_Index
            w["items"].Push(Map("name", WDec(IniRead(WID_FILE, isec, "name", "|"))
                , "search", WDec(IniRead(WID_FILE, isec, "search", "|"))))
        }
        Widgets.Push(w)
    }
}

SaveWidgets() {
    try FileDelete(WID_FILE)
    IniWrite(Widgets.Length, WID_FILE, "General", "count")
    for i, w in Widgets {
        sec := "Widget" i
        IniWrite(WEnc(w["name"]), WID_FILE, sec, "name")
        IniWrite(w["x"], WID_FILE, sec, "x")
        IniWrite(w["y"], WID_FILE, sec, "y")
        IniWrite(w["items"].Length, WID_FILE, sec, "count")
        for j, it in w["items"] {
            isec := sec "Item" j
            IniWrite(WEnc(it["name"]), WID_FILE, isec, "name")
            IniWrite(WEnc(it["search"]), WID_FILE, isec, "search")
        }
    }
}

; ---- open / close ----

ToggleWidgets() {
    if !Settings["widgetsEnabled"]
        return
    if WidgetsOpen
        CloseWidgets()
    else
        OpenWidgets()
}

OpenWidgets() {
    global WidgetsOpen, WdShown
    ; Build everything first and only then flag it open. Building takes a while, and the visibility
    ; timer / focus events can fire meanwhile; if they saw "open" with the toolbar not built yet they
    ; would mark everything shown without it, and the final SyncWidgets would then find nothing to do.
    WdShown := false
    for w in Widgets
        BuildWidget(w)
    BuildToolbar()
    WidgetsOpen := true
    SyncWidgets(WantOverlay())
}

CloseWidgets() {
    global WidgetsOpen, WdShown, WdToolbar
    CloseWdDlg()
    WidgetsOpen := false
    WdShown := false
    for w in Widgets
        DestroyWidgetGui(w)
    if WdToolbar {
        g := WdToolbar
        WdToolbar := ""
        g.Destroy()
    }
}

; Called from UpdateVisibility: widgets follow the overlay, but only while they are open.
SyncWidgets(want) {
    global WdShown
    shown := (WidgetsOpen && want) ? true : false
    if shown = WdShown
        return
    WdShown := shown
    for w in Widgets {
        if !(w.Has("gui") && w["gui"])
            continue
        if shown
            ShowWidget(w)
        else
            w["gui"].Hide()
    }
    if WdToolbar {
        if shown
            ShowToolbar()
        else
            WdToolbar.Hide()
    }
}

DestroyWidgetGui(w) {
    if w.Has("gui") && w["gui"] {
        g := w["gui"]
        w["gui"] := ""   ; clear first: Destroy() triggers events that look at the widget's gui
        g.Destroy()
    }
}

; ---- building ----

WdFontPt() {
    return Round(WD_FONT_PX * 72 / A_ScreenDPI, 1)
}

; Widest of the given strings in the widget font, in pixels (an unshown scratch window measures them).
MeasureText(texts, weight := "norm") {
    g := Gui("-DPIScale")
    g.SetFont("s" WdFontPt() " " weight, "Segoe UI")
    best := 0
    for t in texts {
        c := g.AddText(, t)   ; no width given: the control sizes itself to the text
        c.GetPos(, , &cw)
        best := Max(best, cw)
    }
    g.Destroy()
    return best
}

NoFade(g) {
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 3, "Int*", 1, "UInt", 4)   ; no Windows fade
}

BuildWidget(w) {
    old := w.Has("gui") ? w["gui"] : ""
    items := w["items"]
    names := []
    for it in items
        names.Push(it["name"])
    wd := Max(WD_MIN_W
        , items.Length ? MeasureText(names) + 24 : 0
        , MeasureText([w["name"]], "bold") + 12 + 2 * WD_CTRL_W)

    ; +E0x08000000 = never take focus on click, so PoE keeps it
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
    g.BackColor := "1C1C1C"
    NoFade(g)
    g.MarginX := 0, g.MarginY := 0
    pt := WdFontPt()
    g.SetFont("s" pt " c2A2012 bold", "Segoe UI")   ; dark bold text on the gold title bar
    hit := Map()   ; control hwnd -> item index (for right-click)

    title := g.AddText("x0 y0 w" (wd - 2 * WD_CTRL_W) " h" WD_TITLE_H " +0x100 +0x200 +0x80 BackgroundC8AA6E", "  " w["name"])
    g.SetFont("s" pt " norm", "Segoe UI Symbol")
    bEdit := g.AddText("x" (wd - 2 * WD_CTRL_W) " y0 w" WD_CTRL_W " h" WD_TITLE_H " +0x100 +0x200 Center BackgroundC8AA6E", "✎")
    bDel := g.AddText("x" (wd - WD_CTRL_W) " y0 w" WD_CTRL_W " h" WD_TITLE_H " +0x100 +0x200 Center BackgroundC8AA6E", "✕")
    g.SetFont("s" pt " cE8E8E8 norm", "Segoe UI")   ; light text for the items
    bEdit.OnEvent("Click", (*) => WidgetDialog(w))
    bDel.OnEvent("Click", (*) => DeleteWidget(w))

    y := WD_TITLE_H + WD_GAP
    for i, it in items {
        c := g.AddText("x0 y" y " w" wd " h" WD_ROW_H " +0x100 +0x200 +0x80 Background2B3345", "  " it["name"])
        c.OnEvent("Click", ItemClick.Bind(w, i))
        c.OnEvent("DoubleClick", ItemClick.Bind(w, i))
        hit[c.Hwnd] := i
        y += WD_ROW_H + WD_GAP
    }
    add := g.AddText("x0 y" y " w" wd " h" WD_ROW_H " +0x100 +0x200 Center c9AA3B5 Background20242E", "+ Add search")
    add.OnEvent("Click", (*) => ItemDialog(w, 0))
    g.OnEvent("ContextMenu", WidgetContext.Bind(w))

    w["w"] := wd
    w["h"] := y + WD_ROW_H
    w["hit"] := hit
    w["titleHwnd"] := title.Hwnd
    w["gui"] := g
    if WdShown
        ShowWidget(w)
    if old
        old.Destroy()
}

ShowWidget(w) {
    x := Max(0, Min(w["x"], A_ScreenWidth - 40))
    y := Max(0, Min(w["y"], A_ScreenHeight - 40))
    w["gui"].Show("NA x" x " y" y " w" w["w"] " h" w["h"])
}

BuildToolbar() {
    global WdToolbar
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
    g.BackColor := "20242E"   ; same dark blue as the "+ Add search" row
    NoFade(g)
    g.MarginX := 0, g.MarginY := 0
    pt := WdFontPt()
    ; the buttons are text controls in the item-row blue (native buttons can't be recoloured)
    g.SetFont("s" pt " cE8E8E8 bold", "Segoe UI")
    g.AddText("x10 y10 w120 h30 +0x100 +0x200 Center Background2B3345", "+ New widget").OnEvent("Click", (*) => NewWidget())
    g.SetFont("s" pt " c9AA3B5 norm", "Segoe UI")
    g.AddText("x142 y10 w210 h30 +0x200 +0x80", "Right-click an item or title to edit")
    g.SetFont("s" pt " cE8E8E8 bold", "Segoe UI")
    g.AddText("x360 y10 w70 h30 +0x100 +0x200 Center Background2B3345", "Close").OnEvent("Click", (*) => CloseWidgets())
    WdToolbar := g
    if WdShown
        ShowToolbar()
}

; The PoE window rectangle, or the whole screen when PoE isn't running.
PoeRect(&x, &y, &w, &h) {
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_class POEWindowClass")
        return
    }
    x := 0, y := 0, w := A_ScreenWidth, h := A_ScreenHeight
}

ShowToolbar() {
    PoeRect(&px, &py, &pw, &ph)
    WdToolbar.Show("NA x" (px + (pw - TB_W) // 2) " y" (py + ph - TB_H - 40) " w" TB_W " h" TB_H)
}

; ---- actions ----

ItemClick(w, i, *) {
    if i <= w["items"].Length {
        SendSearch(w["items"][i]["search"])
        CloseWidgets()   ; a search is a one-shot: get the widgets out of the way
    }
}

; Right-click: an item opens its edit dialog, the title opens the widget dialog.
WidgetContext(w, g, ctrl, item, isRight, x, y) {
    if !ctrl
        return
    if w["hit"].Has(ctrl.Hwnd)
        ItemDialog(w, w["hit"][ctrl.Hwnd])
    else if ctrl.Hwnd = w["titleHwnd"]
        WidgetDialog(w)
}

NewWidget() {
    PoeRect(&px, &py, &pw, &ph)
    n := Mod(Widgets.Length, 6)
    w := Map("name", "New widget"
        , "x", px + pw // 2 - 75 + n * 24
        , "y", py + ph // 2 - 60 + n * 24
        , "items", [])
    Widgets.Push(w)
    SaveWidgets()
    BuildWidget(w)
    WidgetDialog(w)
}

DeleteWidget(w) {
    n := w["items"].Length
    if n && MsgBox("Delete the widget '" w["name"] "' and its " n " search" (n = 1 ? "" : "es") "?"
        , "PoE Overlay", "YesNo Icon? 262144") != "Yes"
        return
    for i, x in Widgets {
        if x = w {
            Widgets.RemoveAt(i)
            break
        }
    }
    DestroyWidgetGui(w)
    SaveWidgets()
}

; ---- dialogs (real windows: no-activate windows can't take keyboard input) ----

CloseWdDlg() {
    global WdDlg
    g := WdDlg
    if !g
        return
    WdDlg := ""   ; clear first: Destroy() triggers a foreground-change event that reads WdDlg.Hwnd
    g.Destroy()
    if WinExist("ahk_class POEWindowClass")
        WinActivate("ahk_class POEWindowClass")
}

; A change to a widget is done: save, redraw it, close the dialog.
FinishEdit(w) {
    SaveWidgets()
    BuildWidget(w)
    CloseWdDlg()
}

; idx = 0: add a search; otherwise edit that one (also delete / move)
ItemDialog(w, idx) {
    global WdDlg
    CloseWdDlg()
    isNew := idx = 0
    g := WdDlg := Gui("+AlwaysOnTop", isNew ? "New search" : "Edit search")
    g.SetFont("s9", "Segoe UI")
    g.AddText("w60", "Name")
    edName := g.AddEdit("x+4 yp-3 w320", isNew ? "" : w["items"][idx]["name"])
    g.AddText("xm w60", "Search")
    edSearch := g.AddEdit("x+4 yp-3 w320", isNew ? "" : w["items"][idx]["search"])
    g.AddText("xm cGray", "Leave the name empty to use the search string as the name.")
    g.AddButton("xm y+14 w80 Default", "Save").OnEvent("Click", OnSave)
    g.AddButton("x+6 w80", "Cancel").OnEvent("Click", (*) => CloseWdDlg())
    if !isNew {
        g.AddButton("x+24 w70", "Delete").OnEvent("Click", OnDelete)
        g.AddButton("x+6 w70", "Move up").OnEvent("Click", (*) => OnMove(-1))
        g.AddButton("x+6 w80", "Move down").OnEvent("Click", (*) => OnMove(1))
    }
    g.OnEvent("Close", (*) => CloseWdDlg())
    g.OnEvent("Escape", (*) => CloseWdDlg())
    g.Show()

    OnSave(*) {
        search := Trim(edSearch.Value)
        if search = "" {
            MsgBox("Enter a search string.", "PoE Overlay", "Icon! 262144")
            return
        }
        name := Trim(edName.Value)
        item := Map("name", name != "" ? name : search, "search", search)
        if isNew
            w["items"].Push(item)
        else
            w["items"][idx] := item
        FinishEdit(w)
    }
    OnDelete(*) {
        w["items"].RemoveAt(idx)
        FinishEdit(w)
    }
    OnMove(dir) {
        j := idx + dir
        if j < 1 || j > w["items"].Length
            return
        tmp := w["items"][idx]
        w["items"][idx] := w["items"][j]
        w["items"][j] := tmp
        FinishEdit(w)
    }
}

WidgetDialog(w) {
    global WdDlg
    CloseWdDlg()
    g := WdDlg := Gui("+AlwaysOnTop", "Widget")
    g.SetFont("s9", "Segoe UI")
    g.AddText("w60", "Name")
    edName := g.AddEdit("x+4 yp-3 w260", w["name"])
    g.AddButton("xm y+14 w80 Default", "Save").OnEvent("Click", OnSave)
    g.AddButton("x+6 w80", "Cancel").OnEvent("Click", (*) => CloseWdDlg())
    g.AddButton("x+24 w110", "Delete widget").OnEvent("Click", OnDelete)
    g.OnEvent("Close", (*) => CloseWdDlg())
    g.OnEvent("Escape", (*) => CloseWdDlg())
    g.Show()

    OnSave(*) {
        name := Trim(edName.Value)
        if name != ""
            w["name"] := name
        FinishEdit(w)
    }
    OnDelete(*) {
        CloseWdDlg()
        DeleteWidget(w)
    }
}

; ---- mouse: drag by the title, and keep the game's cursor over the panels ----

OnWidgetDown(wParam, lParam, msg, hwnd) {
    for w in Widgets {
        if w.Has("gui") && w["gui"] && hwnd = w["titleHwnd"] {
            PostMessage(0xA1, 2, , , "ahk_id " w["gui"].Hwnd)   ; WM_NCLBUTTONDOWN, HTCAPTION -> drag
            return
        }
    }
}

OnWidgetDragEnd(wParam, lParam, msg, hwnd) {
    for w in Widgets {
        if w.Has("gui") && w["gui"] && hwnd = w["gui"].Hwnd {
            WinGetPos(&x, &y, , , "ahk_id " hwnd)
            w["x"] := x
            w["y"] := y
            SaveWidgets()
            return
        }
    }
}

OnWidgetCursor(wParam, lParam, msg, hwnd) {
    ctl := GuiCtrlFromHwnd(wParam)
    g := ctl ? ctl.Gui : GuiFromHwnd(wParam)
    if !g
        return
    for w in Widgets {
        if !(w.Has("gui") && w["gui"] && w["gui"] == g)
            continue
        if ctl && ctl.Hwnd = w["titleHwnd"] {
            DllCall("SetCursor", "Ptr", DllCall("LoadCursor", "Ptr", 0, "Ptr", 32646, "Ptr"))   ; IDC_SIZEALL
            return true
        }
        if GameCursor != "" {
            DllCall("SetCursor", "Ptr", GameCursor)
            return true
        }
        return
    }
}

OnMessage(0x201, OnWidgetDown)       ; WM_LBUTTONDOWN
OnMessage(0x232, OnWidgetDragEnd)    ; WM_EXITSIZEMOVE
OnMessage(0x20, OnWidgetCursor)      ; WM_SETCURSOR

; Esc closes the widgets, but only while they are showing over PoE, so Esc keeps its normal job otherwise.
; (It is swallowed in that case, so PoE doesn't also close the stash.)
WidgetsEscActive(*) {
    return WdShown && IsPoeActive()
}
HotIf(WidgetsEscActive)
Hotkey("$Escape", (*) => CloseWidgets())
HotIf()
