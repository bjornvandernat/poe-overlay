#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)

#Include lib\version.ahk
#Include lib\config.ahk
#Include lib\commands.ahk
#Include lib\settings.ahk
#Include lib\overlay.ahk
#Include lib\updater.ahk

A_TrayMenu.Delete()   ; drop AutoHotkey's standard items
A_TrayMenu.Add("Settings", ShowSettings)
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Check for updates", (*) => CheckForUpdates(true))
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Settings"   ; double-click on the tray icon
A_IconTip := "PoE Overlay v" APP_VERSION
if FileExist(A_ScriptDir "\icons\tray.ico")
    TraySetIcon(A_ScriptDir "\icons\tray.ico")

LoadConfig()
RegisterHotkeys()
BuildOverlay()
InitUpdater()
SetTimer(UpdateVisibility, 250)
