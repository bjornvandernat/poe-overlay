#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)

#Include lib\version.ahk
#Include lib\config.ahk
#Include lib\commands.ahk
#Include lib\settings.ahk
#Include lib\overlay.ahk

A_TrayMenu.Insert("1&", "Settings", ShowSettings)
A_TrayMenu.Insert("2&", "Reload", (*) => Reload())
A_TrayMenu.Insert("3&")
A_IconTip := "PoE Overlay v" APP_VERSION
if FileExist(A_ScriptDir "\icons\tray.ico")
    TraySetIcon(A_ScriptDir "\icons\tray.ico")

LoadConfig()
RegisterHotkeys()
BuildOverlay()
SetTimer(UpdateVisibility, 250)
