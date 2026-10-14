; Version of this install, read from the VERSION file next to the script ("0.0.0" if it is missing)

ReadVersion() {
    try
        v := Trim(FileRead(A_ScriptDir "\VERSION"), " `t`r`n")
    catch
        return "0.0.0"
    return RegExMatch(v, "^\d+(\.\d+)*$") ? v : "0.0.0"
}

global APP_VERSION := ReadVersion()
