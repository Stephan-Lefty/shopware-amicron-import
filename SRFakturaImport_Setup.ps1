# Komplettes Setup fuer den Shopware-Amicron-Bestellimport.
# Fuehrt alle Schritte aus, die bisher von Hand gemacht wurden:
#   0. Falls bereits eine Version installiert ist: Hinweis anzeigen und
#      Bestaetigung (j/n) einholen, bevor ueberschrieben wird. Danach
#      Programmdateien an den festen, dauerhaften Zielort kopieren
#      (falls von woanders aus gestartet, z.B. aus einem entpackten
#      Download-Ordner). Eine bereits vorhandene config.ini am Zielort
#      wird dabei NIE ueberschrieben.
#   1. Python pruefen / installieren (winget, mit Fallback auf Direkt-Download)
#   2. Benoetigte Python-Bibliothek installieren (requests)
#   3. Ordnerstruktur anlegen
#   4. config.ini aus der Vorlage anlegen (falls noch nicht vorhanden) und den
#      import_folder-Pfad automatisch korrekt eintragen
#   5. Desktop-Verknuepfung mit Icon anlegen (inkl. Versionsnummer im Namen).
#      Eine bereits vorhandene aeltere Verknuepfung wird entfernt und neu
#      angelegt - die Position auf dem Desktop muss danach ggf. per Hand
#      neu gesetzt werden (Windows speichert Icon-Positionen nicht
#      zuverlaessig ueber einen Dateinamenswechsel hinweg).
#   6. Bei Erstinstallation oder Versionswechsel: Aenderungsprotokoll auf
#      GitHub im Browser oeffnen, sobald das Konsolenfenster geschlossen wird
#   7. Hinweis anzeigen, dass ZIP-Datei und Entpack-Ordner nach dem
#      Schliessen dieses Fensters manuell geloescht werden koennen
#
# Aufruf: Rechtsklick > "Mit PowerShell ausfuehren", oder per Doppelklick auf
# SRFakturaImport_Setup.bat im selben Ordner. Kann von einem beliebigen Ort
# gestartet werden (z.B. direkt aus einem entpackten ZIP im Downloads-Ordner).

$ErrorActionPreference = "Stop"

Write-Host "=== SRFakturaImport Setup ===" -ForegroundColor Cyan

# --- 0. Vorhandene Installation pruefen, dann Programmdateien an den
#        festen Zielort kopieren ------------------------------------------
$OriginalDir = $PSScriptRoot
$PermanentRoot = "C:\SRFakturaImport\scripts\shopware-amicron-import"
$ChangelogUrl = "https://github.com/Stephan-Lefty/shopware-amicron-import#%C3%A4nderungsprotokoll"
$OpenChangelog = $false

# PID des Elternprozesses (cmd.exe aus der .bat-Datei) - solange dessen
# Fenster offen ist (auch beim "Druecke eine beliebige Taste"-Schritt),
# blockiert es u.a. den Ordner, aus dem es gestartet wurde. Wird fuer das
# verzoegerte Oeffnen des Aenderungsprotokolls benoetigt.
$ParentProcessId = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue).ParentProcessId

if ($OriginalDir -ne $PermanentRoot) {
    $ExistingVersionPath = Join-Path $PermanentRoot "VERSION"
    if (Test-Path $ExistingVersionPath) {
        $ExistingVersion = (Get-Content $ExistingVersionPath -Raw).Trim()
        $NewVersionPath = Join-Path $OriginalDir "VERSION"
        $NewVersion = if (Test-Path $NewVersionPath) { (Get-Content $NewVersionPath -Raw).Trim() } else { "unbekannt" }

        Write-Host ""
        Write-Host "Sie haben bereits die Version $ExistingVersion installiert." -ForegroundColor Yellow
        Write-Host "Achtung: Alle alten Programmdateien am Zielort werden ueberschrieben (Ihre config.ini bleibt erhalten)!" -ForegroundColor Yellow
        $confirm = Read-Host "Moechten Sie die neue Version $NewVersion installieren? (j/n)"
        if ($confirm -notmatch "^[jJ]") {
            Write-Host "Installation abgebrochen." -ForegroundColor Red
            exit 0
        }
        if ($ExistingVersion -ne $NewVersion) { $OpenChangelog = $true }
    } else {
        # Noch keine VERSION-Datei am Zielort gefunden -> Erstinstallation
        $OpenChangelog = $true
    }

    Write-Host "Kopiere Programmdateien nach $PermanentRoot ..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $PermanentRoot | Out-Null

    # Eine bereits vorhandene, evtl. vom Nutzer angepasste config.ini am
    # Zielort niemals ueberschreiben. Nur bei einer Erstinstallation (noch
    # keine config.ini am Zielort) wird die evtl. mitgelieferte config.ini
    # aus dem Quellordner mit uebernommen.
    if (Test-Path (Join-Path $PermanentRoot "config.ini")) {
        Copy-Item -Path (Join-Path $OriginalDir "*") -Destination $PermanentRoot -Recurse -Force -Exclude "config.ini"
        Write-Host "Vorhandene config.ini am Zielort bleibt unveraendert erhalten." -ForegroundColor Green
    } else {
        Copy-Item -Path (Join-Path $OriginalDir "*") -Destination $PermanentRoot -Recurse -Force
    }
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
# Hinweis: Eine aeltere Verknuepfung wird entfernt und neu angelegt (nicht
# umbenannt) - Windows liess sich nicht zuverlaessig dazu bringen, die
# Desktop-Position dabei beizubehalten. Nach einem Update ggf. das neue
# Icon per Hand an die gewuenschte Stelle ziehen.
$VersionPath = Join-Path $ScriptDir "VERSION"
$Version = if (Test-Path $VersionPath) { (Get-Content $VersionPath -Raw).Trim() } else { "" }
$LinkName = if ($Version) { "Shopware Import (v$Version).lnk" } else { "Shopware Import.lnk" }

$DesktopPath = [Environment]::GetFolderPath("Desktop")
$IconPath = Join-Path $ScriptDir "import_orders.ico"
$TargetPy = Join-Path $ScriptDir "import_orders.py"
$LinkPath = Join-Path $DesktopPath $LinkName

# Bewusst ohne -Filter (der Parameter kann bei Klammern/Leerzeichen im
# Dateinamen unzuverlaessig sein) - stattdessen alle Dateien auflisten und
# per -like abgleichen. Erfasst sowohl den alten Namen ("Shopware
# Bestellimport ...") als auch den aktuellen ("Shopware Import ..."), damit
# beim Umstieg auf den kuerzeren Namen keine alte Verknuepfung liegen bleibt.
Get-ChildItem -Path $DesktopPath -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "Shopware*Import*.lnk" -and $_.FullName -ne $LinkPath } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($LinkPath)
$Shortcut.TargetPath = $TargetPy
$Shortcut.WorkingDirectory = $ScriptDir
if (Test-Path $IconPath) { $Shortcut.IconLocation = $IconPath }
$Shortcut.Description = "Holt offene Shopware-Bestellungen und schreibt sie als XML fuer den Amicron-Faktura-Import"
$Shortcut.Save()
Write-Host "Desktop-Verknuepfung angelegt: $LinkPath" -ForegroundColor Green
Write-Host "Hinweis: Falls sich die Icon-Position geaendert hat, bitte per Hand an die gewuenschte Stelle ziehen." -ForegroundColor Yellow

# Windows zwingen, den Desktop neu zu zeichnen, damit die Aenderung sofort
# sichtbar ist (kein manuelles F5 noetig).
try {
    Add-Type -Namespace WinAPI -Name Explorer -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("Shell32.dll")]
public static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);
"@
    [WinAPI.Explorer]::SHChangeNotify(0x8000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
} catch {
    Write-Warning "Desktop konnte nicht automatisch aktualisiert werden - ggf. manuell F5 druecken."
}

Write-Host ""
Write-Host "=== Setup abgeschlossen ===" -ForegroundColor Cyan
Write-Host "Installiert in: $ScriptDir" -ForegroundColor Yellow
Write-Host "Letzter manueller Schritt: config.ini oeffnen und shop_url / client_id / client_secret eintragen." -ForegroundColor Yellow
Write-Host "In Faktura als XML-Ordner einstellen: $ImportFolder" -ForegroundColor Yellow
Write-Host "Optional als Nach-Import-Ordner in Faktura: $ErledigtFolder" -ForegroundColor Yellow

# --- 6. Aenderungsprotokoll oeffnen (verzoegert, erst nach Fensterschluss) -
# Bei Erstinstallation oder einer tatsaechlich neuen Version soll sich der
# Browser oeffnen, aber erst NACHDEM das Konsolenfenster (cmd.exe aus der
# .bat-Datei) geschlossen wurde - nicht waehrend der Nutzer noch die
# Setup-Ausgabe liest. Dafuer wartet ein Hintergrundprozess, bis der
# Elternprozess (cmd.exe) beendet ist.
if ($OpenChangelog) {
    Write-Host "Aenderungsprotokoll wird im Browser geoeffnet, sobald dieses Fenster geschlossen wird." -ForegroundColor Cyan
    try {
        $changelogHelper = Join-Path $env:TEMP "srfaktura_changelog_$([guid]::NewGuid().ToString('N')).ps1"
        @"
while (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 500 }
Start-Process '$ChangelogUrl'
Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
"@ | Set-Content -Path $changelogHelper -Encoding UTF8
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", $changelogHelper) `
            -WindowStyle Hidden
    } catch {
        Write-Warning "Aenderungsprotokoll konnte nicht automatisch geoeffnet werden: $ChangelogUrl"
    }
}

# --- 7. Aufraeum-Hinweis (kein automatisches Loeschen mehr) ----------------
if ($OriginalDir -ne $PermanentRoot) {
    Write-Host ""
    Write-Host "Die ZIP-Datei und der entpackte Ordner ($OriginalDir) koennen" -ForegroundColor Cyan
    Write-Host "nach dem Schliessen dieses Fensters manuell geloescht werden." -ForegroundColor Cyan
}
