Set objShell = CreateObject("Wscript.Shell")
scriptPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptPath & "\monitoramento_conexoes.ps1"
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & ps1 & """", 0, False
