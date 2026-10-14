; Self-update from GitHub releases. Never installs anything without the user's confirmation.
;
; Flow: a background check (curl, polled by a timer, so it never blocks) finds a newer release ->
; tray balloon (only while PoE is not focused) + tray menu entry -> confirmation dialog ->
; download, extract, verify, back up, copy over the install (settings.ini is not in the zip,
; so it is untouched), roll back on any error -> reload.

global UPDATE_REPO := "bjornvandernat/poe-travel-overlay"
global UpdateVersion := ""        ; newer version that was found ("" = none)
global UpdateUrl := ""            ; download URL of its zip asset
global UpdateNotified := false    ; balloon already shown for UpdateVersion
global UpdateTrayLabel := ""
global UpdateGui := ""
global UpCheck := Map()           ; the running check: pid, file, manual, start

InitUpdater() {
    OnMessage(0x404, OnTrayNotify)               ; AHK_NOTIFYICON: click on the balloon
    SetTimer(UpdateTick, 5000)
    SetTimer(AutoCheck, 6 * 3600 * 1000)
    SetTimer(StartupCheck, -5000)
}

StartupCheck() {
    AutoCheck()
}

AutoCheck() {
    if Settings["autoUpdate"]
        CheckForUpdates(false)
}

UpdateTempDir() {
    return A_Temp "\poe-travel-overlay-update"
}

; "1.10.0" vs "1.9.0": compared part by part as numbers. Returns 1, 0 or -1.
CompareVersions(a, b) {
    pa := StrSplit(a, "."), pb := StrSplit(b, ".")
    Loop Max(pa.Length, pb.Length) {
        x := pa.Has(A_Index) ? Integer(pa[A_Index]) : 0
        y := pb.Has(A_Index) ? Integer(pb[A_Index]) : 0
        if x != y
            return x > y ? 1 : -1
    }
    return 0
}

; ---- checking ----

CheckForUpdates(manual := false) {
    global UpCheck
    if UpCheck.Count
        return
    dir := UpdateTempDir()
    DirCreate(dir)
    file := dir "\latest.json"
    try FileDelete(file)
    url := "https://api.github.com/repos/" UPDATE_REPO "/releases/latest"
    cmd := Format('"{1}\System32\curl.exe" -fsSL --connect-timeout 5 --max-time 15 -H "Accept: application/vnd.github+json" -o "{2}" "{3}"'
        , A_WinDir, file, url)
    try {
        Run(cmd, , "Hide", &pid)
    } catch {
        if manual
            MsgBox("Couldn't check for updates.", "PoE Overlay", "Icon!")
        return
    }
    UpCheck := Map("pid", pid, "file", file, "manual", manual, "start", A_TickCount)
    SetTimer(PollCheck, 250)
}

PollCheck() {
    global UpCheck
    if ProcessExist(UpCheck["pid"]) && A_TickCount - UpCheck["start"] < 20000
        return
    SetTimer(PollCheck, 0)
    ProcessClose(UpCheck["pid"])
    manual := UpCheck["manual"], file := UpCheck["file"]
    UpCheck := Map()
    json := ""
    try json := FileRead(file, "UTF-8")
    HandleRelease(json, manual)
}

HandleRelease(json, manual) {
    global UpdateVersion, UpdateUrl, UpdateNotified
    asset := '"browser_download_url"\s*:\s*"(https://github\.com/' UPDATE_REPO '/releases/download/[^"]+\.zip)"'
    if !RegExMatch(json, '"tag_name"\s*:\s*"v?(\d+(?:\.\d+)*)"', &tag) || !RegExMatch(json, asset, &zip) {
        if manual
            MsgBox("Couldn't check for updates. Are you online?", "PoE Overlay", "Icon!")
        return
    }
    ver := tag[1]
    if CompareVersions(ver, APP_VERSION) <= 0 {
        UpdateVersion := ""
        RefreshUpdateTray()
        if manual
            MsgBox("You're up to date (v" APP_VERSION ").", "PoE Overlay")
        return
    }
    if !manual && ver = SkippedVersion
        return
    if ver != UpdateVersion
        UpdateNotified := false
    UpdateVersion := ver
    UpdateUrl := zip[1]
    RefreshUpdateTray()
    if manual
        ShowUpdateDialog()
}

; ---- notifying ----

RefreshUpdateTray() {
    global UpdateTrayLabel
    if UpdateTrayLabel != "" {
        try A_TrayMenu.Delete(UpdateTrayLabel)
        UpdateTrayLabel := ""
    }
    A_IconTip := "PoE Overlay v" APP_VERSION
    if UpdateVersion != "" {
        UpdateTrayLabel := "Update available: v" UpdateVersion
        A_TrayMenu.Insert("1&", UpdateTrayLabel, (*) => ShowUpdateDialog())
        A_IconTip .= " (update available)"
    }
}

; Balloon once per version, and never while PoE is focused.
UpdateTick() {
    global UpdateNotified
    if UpdateVersion != "" && !UpdateNotified && !IsPoeActive() {
        UpdateNotified := true
        TrayTip("Click to review and install it.", "PoE Overlay v" UpdateVersion " is available")
    }
}

OnTrayNotify(wParam, lParam, msg, hwnd) {
    if lParam = 1029 && UpdateVersion != ""   ; NIN_BALLOONUSERCLICK
        ShowUpdateDialog()
}

; ---- confirmation ----

ShowUpdateDialog() {
    global UpdateGui
    if UpdateVersion = ""
        return
    if UpdateGui {
        UpdateGui.Show()
        return
    }
    g := UpdateGui := Gui("+AlwaysOnTop", "PoE Overlay update")
    g.SetFont("s9", "Segoe UI")
    g.AddText("w330", "Version " UpdateVersion " is available (you have " APP_VERSION ").`n"
        "Install it now? Your settings are kept and the overlay restarts.")
    g.AddButton("xm y+14 w100 Default", "Update now").OnEvent("Click", (*) => (CloseUpdateGui(), ApplyUpdate()))
    g.AddButton("x+6 w80", "Later").OnEvent("Click", (*) => CloseUpdateGui())
    g.AddButton("x+6 w120", "Skip this version").OnEvent("Click", SkipVersion)
    g.OnEvent("Close", (*) => CloseUpdateGui())
    g.OnEvent("Escape", (*) => CloseUpdateGui())
    g.Show()
}

CloseUpdateGui() {
    global UpdateGui
    if UpdateGui {
        UpdateGui.Destroy()
        UpdateGui := ""
    }
}

SkipVersion(*) {
    global SkippedVersion, UpdateVersion
    SkippedVersion := UpdateVersion
    UpdateVersion := ""
    SaveConfig()
    RefreshUpdateTray()
    CloseUpdateGui()
}

; ---- installing ----

ApplyUpdate() {
    ver := UpdateVersion, url := UpdateUrl
    tmp := UpdateTempDir()
    stage := tmp "\stage", zip := tmp "\update.zip"
    try DirDelete(tmp, true)
    DirCreate(stage)
    sys := A_WinDir "\System32"
    TrayTip("Downloading v" ver "...", "PoE Overlay")
    try {
        if RunWait(Format('"{1}\curl.exe" -fsSL --connect-timeout 10 --max-time 120 -o "{2}" "{3}"', sys, zip, url), , "Hide") != 0
            throw Error("The download failed.")
        if RunWait(Format('"{1}\tar.exe" -xf "{2}" -C "{3}"', sys, zip, stage), , "Hide") != 0
            throw Error("The downloaded file could not be extracted.")
        if !FileExist(stage "\overlay.ahk") || !FileExist(stage "\lib\overlay.ahk")
            throw Error("The downloaded update is incomplete.")
        if Trim(FileRead(stage "\VERSION"), " `t`r`n") != ver
            throw Error("The downloaded update has an unexpected version.")
        InstallStaged(stage, tmp "\backup")
    } catch as e {
        detail := e.Message (e.Extra != "" ? "`n" e.Extra : "") "`n(" e.What ", line " e.Line ")"
        MsgBox("The update failed, so nothing was changed.`n`n" detail "`n`nYou are still on v" APP_VERSION ".", "PoE Overlay", "Icon!")
        return
    }
    MsgBox("Updated to v" ver ". The overlay will now restart.", "PoE Overlay")
    Reload()
}

; Copy every staged file over the install, backing up what it replaces. Undo it all on failure.
InstallStaged(stage, backup) {
    files := []
    Loop Files, stage "\*", "FR"
        files.Push(SubStr(A_LoopFileFullPath, StrLen(stage) + 2))
    done := []   ; [relative path, existed before]
    try {
        for rel in files {
            dst := A_ScriptDir "\" rel
            SplitPath(rel, , &relDir)
            existed := FileExist(dst) ? true : false
            if existed {
                DirCreate(backup (relDir != "" ? "\" relDir : ""))
                FileCopy(dst, backup "\" rel, 1)
            }
            DirCreate(A_ScriptDir (relDir != "" ? "\" relDir : ""))
            FileCopy(stage "\" rel, dst, 1)
            done.Push([rel, existed])
        }
    } catch as e {
        Loop done.Length {
            item := done[done.Length - A_Index + 1]
            try {
                if item[2]
                    FileCopy(backup "\" item[1], A_ScriptDir "\" item[1], 1)
                else
                    FileDelete(A_ScriptDir "\" item[1])
            }
        }
        throw e
    }
}
