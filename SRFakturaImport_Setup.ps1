# Komplettes Setup fuer den Shopware-Amicron-Bestellimport.
# Fuehrt alle Schritte aus, die bisher von Hand gemacht wurden:
#   0. Programmdateien an den festen, dauerhaften Zielort kopieren
#      (falls von woanders aus gestartet, z.B. aus einem entpackten
#      Download-Ordner)
#   1. Python pruefen / installieren (winget, mit Fallback auf Direkt-Download)
#   2. Benoetigte Python-Bibliothek installieren (requests)
#   3. Ordnerstruktur anlegen
#   4. config.ini aus der Vorlage anlegen (falls noch nicht vorhanden) und den
#      import_folder-Pfad automatisch korrekt eintragen
#   5. Desktop-Verknuepfung mit Icon anlegen (inkl. Versionsnummer im Namen)
#   6. Optional: urspruenglichen Download-/Entpack-Ordner und ZIP-Datei in
#      den Papierkorb verschieben
#
# Aufruf: Rechtsklick > "Mit PowerShell ausfuehren", oder per Doppelklick auf
# SRFakturaImport_Setup.bat im selben Ordner. Kann von einem beliebigen Ort
# gestartet werden (z.B. direkt aus einem entpackten ZIP im Downloads-Ordner).

$ErrorActionPreference = "Stop"

Write-Host "=== SRFakturaImport Setup ===" -ForegroundColor Cyan

# --- 0. Programmdateien an den festen Zielort kopieren --------------------
$OriginalDir = $PSScriptRoot
$PermanentRoot = "C:\SRFakturaImport\scripts\shopware-amicron-import"

if ($OriginalDir -ne $PermanentRoot) {
    Write-Host "Kopiere Programmdateien nach $PermanentRoot ..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $PermanentRoot | Out-Null
    Copy-Item -Path (Join-Path $OriginalDir "*") -Destination $PermanentRoot -Recurse -Force
    $ScriptDir = $PermanentRoot
} else {
    $ScriptDir = $OriginalDir
}

# --- 1. Python pruefen / installieren -----------------------------------
function Test-PythonAvailable {
    try { python --version *> $null; return $true } catch { return $false }
}

if (-not (Test-PythonAvailable)) {
    Write-Host "Python nicht gefunden, versuche Installation ueber winget..." -ForegroundColor Yellow
    $wingetOk = $false
    try {
        winget install --id Python.Python.3.12 --source winget -e --accept-source-agreements --accept-package-agreements
        $wingetOk = $true
    } catch {
        Write-Warning "winget-Installation fehlgeschlagen, versuche Direkt-Download von python.org..."
    }

    if (-not $wingetOk -or -not (Test-PythonAvailable)) {
        $installerUrl = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
        $installerPath = Join-Path $env:TEMP "python-installer.exe"
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        Start-Process -FilePath $installerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
        Remove-Item $installerPath -ErrorAction SilentlyContinue
    }

    # PATH in dieser Sitzung aus der Registry neu laden, damit python/pip
    # sofort nutzbar sind, ohne die Konsole neu zu starten.
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

if (-not (Test-PythonAvailable)) {
    Write-Error "Python konnte nicht automatisch installiert werden. Bitte manuell von python.org installieren und dieses Script erneut ausfuehren."
    exit 1
}
Write-Host "Python ist vorhanden: $(python --version)" -ForegroundColor Green

# --- 2. Python-Bibliothek installieren -----------------------------------
Write-Host "Installiere/pruefe 'requests'..." -ForegroundColor Cyan
pip install --quiet requests

# --- 3. Ordnerstruktur anlegen -------------------------------------------
# Fester Pfad (unabhaengig vom Script-Ordner), passend zum produktiv
# eingerichteten und in Faktura hinterlegten Ordner.
$ImportFolder = "C:\SRFakturaImport\amicron\import"
$ErledigtFolder = Join-Path $ImportFolder "erledigt"
New-Item -ItemType Directory -Force -Path $ImportFolder | Out-Null
New-Item -ItemType Directory -Force -Path $ErledigtFolder | Out-Null
Write-Host "Import-Ordner bereit: $ImportFolder" -ForegroundColor Green

# --- 4. config.ini vorbereiten --------------------------------------------
$ConfigPath = Join-Path $ScriptDir "config.ini"
$ExamplePath = Join-Path $ScriptDir "config.ini.example"

if (-not (Test-Path $ConfigPath)) {
    if (Test-Path $ExamplePath) {
        Copy-Item $ExamplePath $ConfigPath
        # import_folder automatisch auf den korrekten, absoluten Pfad setzen
        (Get-Content $ConfigPath) -replace '^import_folder\s*=.*$', "import_folder = $ImportFolder" |
            Set-Content $ConfigPath -Encoding UTF8
        Write-Host "config.ini wurde aus der Vorlage erstellt." -ForegroundColor Yellow
        Write-Host "WICHTIG: Bitte shop_url, client_id und client_secret in config.ini eintragen!" -ForegroundColor Yellow
    } else {
        Write-Warning "config.ini.example wurde nicht gefunden - config.ini muss manuell angelegt werden."
    }
} else {
    Write-Host "config.ini existiert bereits, wird nicht ueberschrieben." -ForegroundColor Green
}

# --- 5. Desktop-Verknuepfung mit Icon (inkl. Versionsnummer im Namen) -----
$VersionPath = Join-Path $ScriptDir "VERSION"
$Version = if (Test-Path $VersionPath) { (Get-Content $VersionPath -Raw).Trim() } else { "" }
$LinkName = if ($Version) { "Shopware Bestellimport (v$Version).lnk" } else { "Shopware Bestellimport.lnk" }

$DesktopPath = [Environment]::GetFolderPath("Desktop")
$IconPath = Join-Path $ScriptDir "import_orders.ico"
$TargetPy = Join-Path $ScriptDir "import_orders.py"
$LinkPath = Join-Path $DesktopPath $LinkName

# Alte Verknuepfungen mit anderer/ohne Versionsnummer entfernen, damit nach
# einem Update nicht mehrere Icons gleichzeitig auf dem Desktop liegen.
Get-ChildItem -Path $DesktopPath -Filter "Shopware Bestellimport*.lnk" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $LinkPath } |
    Remove-Item -Force

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($LinkPath)
$Shortcut.TargetPath = $TargetPy
$Shortcut.WorkingDirectory = $ScriptDir
if (Test-Path $IconPath) { $Shortcut.IconLocation = $IconPath }
$Shortcut.Description = "Holt offene Shopware-Bestellungen und schreibt sie als XML fuer den Amicron-Faktura-Import"
$Shortcut.Save()
Write-Host "Desktop-Verknuepfung angelegt: $LinkPath" -ForegroundColor Green

Write-Host ""
Write-Host "=== Setup abgeschlossen ===" -ForegroundColor Cyan
Write-Host "Installiert in: $ScriptDir" -ForegroundColor Yellow
Write-Host "Letzter manueller Schritt: config.ini oeffnen und shop_url / client_id / client_secret eintragen." -ForegroundColor Yellow
Write-Host "In Faktura als XML-Ordner einstellen: $ImportFolder" -ForegroundColor Yellow
Write-Host "Optional als Nach-Import-Ordner in Faktura: $ErledigtFolder" -ForegroundColor Yellow

# --- 6. Aufraeumen (optional) ----------------------------------------------
if ($OriginalDir -ne $PermanentRoot) {
    Write-Host ""
    $answer = Read-Host "ZIP-Datei und urspruenglichen Entpack-Ordner in den Papierkorb verschieben? (j/n)"
    if ($answer -match "^[jJ]") {
        Add-Type -AssemblyName Microsoft.VisualBasic

        $ZipCandidate = Get-ChildItem -Path (Split-Path $OriginalDir -Parent) -Filter "SRFakturaImport*.zip" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($ZipCandidate) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $ZipCandidate.FullName, "OnlyErrorDialogs", "SendToRecycleBin")
            Write-Host "ZIP-Datei in den Papierkorb verschoben: $($ZipCandidate.FullName)" -ForegroundColor Green
        }

        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $OriginalDir, "OnlyErrorDialogs", "SendToRecycleBin")
        Write-Host "Entpack-Ordner in den Papierkorb verschoben: $OriginalDir" -ForegroundColor Green
        Write-Host "Nur noch das fertig installierte Tool unter $ScriptDir ist vorhanden." -ForegroundColor Green
    }
}
