; Settings panel: a page list on the left ("Travel Buttons", "Search Widgets") and the selected page on the right

global SettingsGui := ""
global Draft := []
global DraftVertical := 0
global DraftLocked := 0
global SLV, edName, edCmd, ddIcon, txHotkey, btnRec, chkVert, chkLock, chkAuto, edScale
global nav, Pages, chkWEnable, txWHotkey, btnWRec
global DraftWHotkey := ""
global ScaleAtOpen := 100
global RecHook := ""
global RecTarget := ""     ; what the running recording is for: "button" (selected row) or "widgets"
global RecBtn := ""        ; its Record button, so the label can be restored
global PAGE_X := 150       ; left edge of the page area (the page list sits to its left)

ShowSettings(*) {
    global SettingsGui, Draft, DraftVertical, DraftLocked, SLV, edName, edCmd, ddIcon, txHotkey, btnRec, chkVert, chkLock, chkAuto, edScale, ScaleAtOpen
    global nav, Pages, chkWEnable, txWHotkey, btnWRec, DraftWHotkey
    if SettingsGui {
        SettingsGui.Show()
        return
    }
    Draft := CloneButtons(Buttons)
    DraftVertical := Settings["vertical"]
    DraftLocked := Settings["locked"]
    DraftWHotkey := WidgetsHotkey

    g := SettingsGui := Gui("+AlwaysOnTop", "PoE Overlay Settings")
    g.SetFont("s9", "Segoe UI")
    nav := g.AddListBox("x10 y10 w130 r3", ["Travel Buttons", "Search Widgets", "Automatic Updates"])
    nav.Choose(1)
    nav.OnEvent("Change", (*) => SwitchPage(nav.Value))
    c0 := ControlCount(g)

    ; ---- page 1: Travel Buttons ----
    SLV := g.AddListView("x" PAGE_X " y10 w520 r8 -Multi Checked", ["Name", "Command", "Hotkey", "Icon"])
    SLV.OnEvent("ItemSelect", (*) => LoadFields())
    g.AddButton("x" PAGE_X " w60", "Add").OnEvent("Click", AddRow)
    g.AddButton("x+6 w60", "Delete").OnEvent("Click", DeleteRow)
    g.AddButton("x+6 w60", "Up").OnEvent("Click", (*) => MoveRow(-1))
    g.AddButton("x+6 w60", "Down").OnEvent("Click", (*) => MoveRow(1))
    chkVert := g.AddCheckbox("x+20 yp+4", "Vertical layout")
    chkVert.Value := DraftVertical
    chkVert.OnEvent("Click", ToggleVertical)
    chkLock := g.AddCheckbox("x+14 yp", "Lock overlay")
    chkLock.Value := DraftLocked
    chkLock.OnEvent("Click", ToggleLocked)

    ScaleAtOpen := Settings["scale"]
    g.AddText("x" PAGE_X " y+16 w110 +0x200", "Overlay scale (%)")
    edScale := g.AddEdit("x+4 yp w60 Number")
    g.AddUpDown("Range" SCALE_MIN "-" SCALE_MAX, ScaleAtOpen)
    g.AddText("x+10 yp+3 cGray", SCALE_MIN "-" SCALE_MAX "; you can also drag the corner handle on the overlay")

    grp := g.AddGroupBox("x" PAGE_X " y+16 w520 h130 Section", "Selected button")
    g.AddText("xs+10 ys+24 w60", "Name")
    edName := g.AddEdit("x+4 yp-3 w180")
    edName.OnEvent("Change", FieldChanged)
    g.AddText("x+14 yp+3 w60", "Command")
    edCmd := g.AddEdit("x+4 yp-3 w150")
    edCmd.OnEvent("Change", FieldChanged)
    g.AddText("xs+10 ys+58 w60", "Icon")
    ddIcon := g.AddDropDownList("x+4 yp-3 w180")
    ddIcon.OnEvent("Change", FieldChanged)
    g.AddButton("x+6 yp-1 w70", "Browse...").OnEvent("Click", BrowseIcon)
    g.AddText("xs+10 ys+92 w60", "Hotkey")
    txHotkey := g.AddText("x+4 yp w180 Border Center +0x200", "")
    btnRec := g.AddButton("x+6 yp-2 w90", "Record")
    btnRec.OnEvent("Click", StartRecording.Bind("button"))
    g.AddButton("x+6 w60", "Clear").OnEvent("Click", ClearHotkey)
    c1 := ControlCount(g)

    ; ---- page 2: Search Widgets ----
    chkWEnable := g.AddCheckbox("x" PAGE_X " y10", "Enabled")
    chkWEnable.Value := Settings["widgetsEnabled"]
    g.AddText("x" PAGE_X " y+22 w60 +0x200", "Hotkey")
    txWHotkey := g.AddText("x+4 yp w180 Border Center +0x200", PrettyHotkey(DraftWHotkey))
    btnWRec := g.AddButton("x+6 yp-2 w90", "Record")
    btnWRec.OnEvent("Click", StartRecording.Bind("widgets"))
    g.AddButton("x+6 w60", "Clear").OnEvent("Click", ClearWidgetsHotkey)
    g.AddText("x" PAGE_X " y+14 cGray", "The hotkey opens and closes the widgets while PoE has focus.`nDisabling removes the widgets button from the bar and turns the hotkey off.")
    c2 := ControlCount(g)

    ; ---- page 3: Automatic Updates ----
    chkAuto := g.AddCheckbox("x" PAGE_X " y10", "Check for updates automatically")
    chkAuto.Value := Settings["autoUpdate"]
    g.AddText("x" PAGE_X " y+22 w110 +0x200", "Installed version")
    g.AddText("x+4 yp w120 +0x200", APP_VERSION)
    g.AddButton("x" PAGE_X " y+16 w110", "Check now").OnEvent("Click", (*) => CheckForUpdates(true))
    g.AddText("x" PAGE_X " y+16 cGray", "The overlay looks for a newer release on GitHub shortly after it starts and then every few hours.`nNothing is installed without your confirmation.")
    c3 := ControlCount(g)

    Pages := [SliceControls(g, c0, c1), SliceControls(g, c1, c2), SliceControls(g, c2, c3)]

    ; the page list is as tall as the first page; the button row sits under both
    grp.GetPos(, &gy, , &gh)
    nav.Move(, , , gy + gh - 10)
    by := gy + gh + 22
    ; Ko-fi on the left, Save/Cancel right-aligned with the 520px pages (2 x 90 + 6 gap = 186)
    kofi := A_ScriptDir "\images\btn-kofi.png"
    if FileExist(kofi) {
        g.AddPicture("x10 y" by " h32 w-1 +0x100", kofi).OnEvent("Click", (*) => Run("https://ko-fi.com/P5P21SSZ5N"))
        g.AddButton("x" (PAGE_X + 520 - 186) " y" (by + 4) " w90 Default", "Save").OnEvent("Click", SaveSettings)
    } else
        g.AddButton("x" (PAGE_X + 520 - 186) " y" by " w90 Default", "Save").OnEvent("Click", SaveSettings)
    g.AddButton("x+6 w90", "Cancel").OnEvent("Click", CloseSettings)
    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    RefreshList(1)
    SwitchPage(1)
    g.Show()
}

; Number of controls in the window so far; a page is the controls created between two counts
; (a Gui enumerates its controls in creation order).
ControlCount(g) {
    n := 0
    for hwnd, ctl in g
        n++
    return n
}

SliceControls(g, from, to) {
    out := []
    i := 0
    for hwnd, ctl in g {
        i++
        if i > from && i <= to
            out.Push(ctl)
    }
    return out
}

SwitchPage(n) {
    StopRecording()
    for i, ctls in Pages
        for ctl in ctls
            ctl.Visible := (i = n)
}

ToggleVertical(*) {
    global DraftVertical
    DraftVertical := chkVert.Value
}

ToggleLocked(*) {
    global DraftLocked
    DraftLocked := chkLock.Value
}

CloseSettings(*) {
    global SettingsGui
    StopRecording()
    g := SettingsGui
    SettingsGui := ""   ; clear first: Destroy() triggers a foreground-change event that reads SettingsGui.Hwnd
    g.Destroy()
}

SaveSettings(*) {
    global Buttons, WidgetsHotkey
    StopRecording()
    SyncChecks()
    Buttons := CloneButtons(Draft)
    Settings["vertical"] := DraftVertical
    Settings["locked"] := DraftLocked
    Settings["autoUpdate"] := chkAuto.Value
    Settings["widgetsEnabled"] := chkWEnable.Value
    WidgetsHotkey := DraftWHotkey
    if !Settings["widgetsEnabled"] && WidgetsOpen
        CloseWidgets()
    ; only apply the scale if it was edited here (it may have been changed via the corner handle meanwhile)
    v := edScale.Value
    if IsInteger(v) && v != ScaleAtOpen
        Settings["scale"] := Max(SCALE_MIN, Min(SCALE_MAX, Integer(v)))
    SaveConfig()
    RegisterHotkeys()
    BuildOverlay()
    CloseSettings()
}

; Copy the ListView checkboxes into Draft. Called before anything that changes or saves the list
; (reading the state directly is more reliable than reacting to ItemCheck events).
SyncChecks() {
    for i, b in Draft
        b["enabled"] := 0
    row := 0
    while row := SLV.GetNext(row, "Checked")
        if row <= Draft.Length
            Draft[row]["enabled"] := 1
}

RefreshList(select := 0) {
    SLV.Delete()
    for b in Draft
        SLV.Add(b["enabled"] ? "Check" : "", b["name"], b["command"], PrettyHotkey(b["hotkey"]), b["icon"])
    SLV.ModifyCol(1, 110), SLV.ModifyCol(2, 130), SLV.ModifyCol(3, 120), SLV.ModifyCol(4, 140)
    if select && select <= Draft.Length
        SLV.Modify(select, "Select Focus Vis")
    LoadFields()
}

SelectedIndex() {
    return SLV.GetNext()
}

LoadFields() {
    StopRecording()
    i := SelectedIndex()
    en := i ? true : false
    for ctl in [edName, edCmd, ddIcon, btnRec]
        ctl.Enabled := en
    if !i {
        edName.Value := edCmd.Value := txHotkey.Text := ""
        return
    }
    b := Draft[i]
    edName.Value := b["name"]
    edCmd.Value := b["command"]
    txHotkey.Text := PrettyHotkey(b["hotkey"])
    FillIconList(b["icon"])
}

FillIconList(current) {
    ddIcon.Delete()
    names := []
    Loop Files, ICON_DIR "\*.png"
        names.Push(A_LoopFileName)
    if current != "" {
        found := false
        for n in names
            if n = current
                found := true
        if !found
            names.Push(current)
    }
    if names.Length
        ddIcon.Add(names)
    try ddIcon.Choose(current)
}

FieldChanged(*) {
    i := SelectedIndex()
    if !i
        return
    b := Draft[i]
    b["name"] := edName.Value
    b["command"] := edCmd.Value
    if ddIcon.Text != ""
        b["icon"] := ddIcon.Text
    SLV.Modify(i, , b["name"], b["command"], PrettyHotkey(b["hotkey"]), b["icon"])
}

BrowseIcon(*) {
    i := SelectedIndex()
    if !i
        return
    file := FileSelect(1, ICON_DIR, "Choose an icon", "Images (*.png; *.jpg; *.bmp; *.ico)")
    if file = ""
        return
    SplitPath(file, &name, &dir)
    Draft[i]["icon"] := (dir = ICON_DIR) ? name : file
    FillIconList(Draft[i]["icon"])
    FieldChanged()
}

AddRow(*) {
    SyncChecks()
    Draft.Push(NewButton("New", "plus.png", "/"))
    RefreshList(Draft.Length)
}

DeleteRow(*) {
    SyncChecks()
    i := SelectedIndex()
    if !i
        return
    Draft.RemoveAt(i)
    RefreshList(Min(i, Draft.Length))
}

MoveRow(dir) {
    SyncChecks()
    i := SelectedIndex()
    j := i + dir
    if !i || j < 1 || j > Draft.Length
        return
    tmp := Draft[i], Draft[i] := Draft[j], Draft[j] := tmp
    RefreshList(j)
}

; ---- hotkey recording ----

; which: "button" records for the selected row, "widgets" for the search widgets hotkey
StartRecording(which, *) {
    global RecHook, RecTarget, RecBtn
    if which = "button" && !SelectedIndex()
        return
    StopRecording()
    RecTarget := which
    RecBtn := which = "widgets" ? btnWRec : btnRec
    RecBtn.Text := "Press keys..."
    RecHook := InputHook("L0 T10")
    RecHook.KeyOpt("{All}", "NS")
    RecHook.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-S")
    RecHook.OnKeyDown := OnRecKey
    RecHook.OnEnd := (*) => (RecBtn.Text := "Record")
    RecHook.Start()
}

StopRecording() {
    global RecHook
    if RecHook {
        RecHook.OnEnd := ""
        RecHook.Stop()
        RecHook := ""
        try RecBtn.Text := "Record"
    }
}

OnRecKey(ih, vk, sc) {
    global DraftWHotkey
    name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if RegExMatch(name, "i)^(Control|Ctrl|Alt|Shift|LWin|RWin|[LR](Control|Alt|Shift))$")
        return
    if name = "Escape" {
        StopRecording()
        return
    }
    mods := (GetKeyState("Ctrl", "P") ? "^" : "") (GetKeyState("Alt", "P") ? "!" : "")
          . (GetKeyState("Shift", "P") ? "+" : "") (GetKeyState("LWin", "P") || GetKeyState("RWin", "P") ? "#" : "")
    hk := mods name
    target := RecTarget
    StopRecording()

    i := SelectedIndex()
    if target = "button" && !i
        return
    if hk = "Enter" {
        MsgBox("Plain Enter is used to open the chat; pick another key.", "Hotkey", "Icon! 262144")
        return
    }
    if target = "widgets" {
        for b in Draft
            if b["hotkey"] = hk {
                MsgBox(PrettyHotkey(hk) " is already used by '" b["name"] "'.", "Hotkey", "Icon! 262144")
                return
            }
        DraftWHotkey := hk
        txWHotkey.Text := PrettyHotkey(hk)
        return
    }
    if hk = DraftWHotkey {
        MsgBox(PrettyHotkey(hk) " is already used by the search widgets.", "Hotkey", "Icon! 262144")
        return
    }
    for idx, b in Draft
        if idx != i && b["hotkey"] = hk {
            MsgBox(PrettyHotkey(hk) " is already used by '" b["name"] "'.", "Hotkey", "Icon! 262144")
            return
        }
    Draft[i]["hotkey"] := hk
    txHotkey.Text := PrettyHotkey(hk)
    FieldChanged()
}

ClearHotkey(*) {
    i := SelectedIndex()
    if !i
        return
    Draft[i]["hotkey"] := ""
    txHotkey.Text := ""
    FieldChanged()
}

ClearWidgetsHotkey(*) {
    global DraftWHotkey
    DraftWHotkey := ""
    txWHotkey.Text := ""
}
