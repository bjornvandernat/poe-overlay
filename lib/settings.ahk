; Settings panel: edit / add / reorder buttons and record hotkeys

global SettingsGui := ""
global Draft := []
global DraftVertical := 0
global SLV, edName, edCmd, ddIcon, txHotkey, btnRec, chkVert
global RecHook := ""

ShowSettings(*) {
    global SettingsGui, Draft, DraftVertical, SLV, edName, edCmd, ddIcon, txHotkey, btnRec, chkVert
    if SettingsGui {
        SettingsGui.Show()
        return
    }
    Draft := CloneButtons(Buttons)
    DraftVertical := Settings["vertical"]

    g := SettingsGui := Gui("+AlwaysOnTop", "PoE Overlay Settings")
    g.SetFont("s9", "Segoe UI")
    SLV := g.AddListView("xm w520 r8 -Multi", ["Name", "Command", "Hotkey", "Icon"])
    SLV.OnEvent("ItemSelect", (*) => LoadFields())
    g.AddButton("xm w60", "Add").OnEvent("Click", AddRow)
    g.AddButton("x+6 w60", "Delete").OnEvent("Click", DeleteRow)
    g.AddButton("x+6 w60", "Up").OnEvent("Click", (*) => MoveRow(-1))
    g.AddButton("x+6 w60", "Down").OnEvent("Click", (*) => MoveRow(1))
    chkVert := g.AddCheckbox("x+20 yp+4", "Vertical layout")
    chkVert.Value := DraftVertical
    chkVert.OnEvent("Click", ToggleVertical)

    g.AddGroupBox("xm w520 h130 Section", "Selected button")
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
    btnRec.OnEvent("Click", StartRecording)
    g.AddButton("x+6 w60", "Clear").OnEvent("Click", ClearHotkey)

    g.AddButton("xm y+22 w90 Default", "Save").OnEvent("Click", SaveSettings)
    g.AddButton("x+6 w90", "Cancel").OnEvent("Click", CloseSettings)
    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    RefreshList(1)
    g.Show()
}

ToggleVertical(*) {
    global DraftVertical
    DraftVertical := chkVert.Value
}

CloseSettings(*) {
    global SettingsGui
    StopRecording()
    SettingsGui.Destroy()
    SettingsGui := ""
}

SaveSettings(*) {
    global Buttons
    StopRecording()
    Buttons := CloneButtons(Draft)
    Settings["vertical"] := DraftVertical
    SaveConfig()
    RegisterHotkeys()
    BuildOverlay()
    CloseSettings()
}

RefreshList(select := 0) {
    SLV.Delete()
    for b in Draft
        SLV.Add(, b["name"], b["command"], PrettyHotkey(b["hotkey"]), b["icon"])
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
    Draft.Push(NewButton("New", "plus.png", "/"))
    RefreshList(Draft.Length)
}

DeleteRow(*) {
    i := SelectedIndex()
    if !i
        return
    Draft.RemoveAt(i)
    RefreshList(Min(i, Draft.Length))
}

MoveRow(dir) {
    i := SelectedIndex()
    j := i + dir
    if !i || j < 1 || j > Draft.Length
        return
    tmp := Draft[i], Draft[i] := Draft[j], Draft[j] := tmp
    RefreshList(j)
}

; ---- hotkey recording ----

StartRecording(*) {
    global RecHook
    if !SelectedIndex()
        return
    StopRecording()
    btnRec.Text := "Press keys..."
    RecHook := InputHook("L0 T10")
    RecHook.KeyOpt("{All}", "NS")
    RecHook.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-S")
    RecHook.OnKeyDown := OnRecKey
    RecHook.OnEnd := (*) => (btnRec.Text := "Record")
    RecHook.Start()
}

StopRecording() {
    global RecHook
    if RecHook {
        RecHook.OnEnd := ""
        RecHook.Stop()
        RecHook := ""
        try btnRec.Text := "Record"
    }
}

OnRecKey(ih, vk, sc) {
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
    StopRecording()

    i := SelectedIndex()
    if !i
        return
    if hk = "Enter" {
        MsgBox("Plain Enter is used to open the chat; pick another key.", "Hotkey", "Icon!")
        return
    }
    for idx, b in Draft
        if idx != i && b["hotkey"] = hk {
            MsgBox(PrettyHotkey(hk) " is already used by '" b["name"] "'.", "Hotkey", "Icon!")
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
