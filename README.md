# Shopware → Amicron Faktura Bestellimport

[Änderungsprotokoll](#änderungsprotokoll)

Ersetzt das alte, mit Shopware 5/älter mitgelieferte Amicron-Script
`af13_shopware.php` (lief im `engine`-Ordner des alten Shops), das mit
Shopware 6 nicht mehr funktioniert. Dieses Tool holt offene Bestellungen
per Shopware-6-Admin-API und übergibt sie Amicron Faktura 13 Pro über den
ganz normalen Datei-Import (`Extras > Datenimport > Aufträge (Datei)`),
mit der bereits vorhandenen **Importdefinition 3**.

## Überblick

```
Shopware 6.7 Admin-API  --->  import_orders.py  --->  XML-Datei  --->  Faktura-Datei-Import (Importdefinition 3)
```

1. `import_orders.py` meldet sich per OAuth2 (Client-Credentials) an der
   Shopware-Admin-API an.
2. Es lädt alle Bestellungen mit Bestellstatus **"offen"**
   (`stateMachineState.technicalName = open`).
3. Für jede Bestellung wird ein `<ORDER>`-Block im Amicron-XML-Format
   erzeugt (Adresse, Artikel, Zahlart, Versandkosten, Verkaufskanal, ...).
4. Die XML-Datei wird in einen lokalen Ordner geschrieben, den Faktura
   überwacht.
5. In Faktura wird die Datei manuell (oder per Scheduler) über den
   XML-Import-Dialog eingelesen.

Das Script läuft **lokal auf dem PC, auf dem auch Faktura bedient wird**
(nicht auf einem Server) — nur so kann Faktura den erzeugten Ordner ohne
Netzwerk-/Berechtigungsprobleme im Datei-Auswahldialog sehen.

## 1. Einrichtung in Shopware 6

1. Admin-Bereich öffnen: **Einstellungen → System → Integrationen**
2. **"Integration anlegen"** klicken, Namen vergeben (z. B.
   `AmicronFakturaImport`)
3. Rechte vergeben: entweder **Administratorrechte** aktivieren (einfach,
   für ein internes Tool vertretbar), oder eine eigene Rolle mit
   Lesezugriff auf **Bestellungen** und **Kunden** anlegen und der
   Integration zuweisen (sauberer, aber aufwändiger einzurichten)
4. Die angezeigte **Access-ID** und den **Secret-Key** sofort notieren —
   der Secret-Key wird danach nicht mehr angezeigt
5. Diese beiden Werte werden später in `config.ini` als `client_id` /
   `client_secret` eingetragen

Es wird keine Änderung an der Shopware-Installation selbst benötigt
(kein Plugin, kein Custom-Script) — nur diese eine Integration.

## 2. Einrichtung in Faktura

Die Feldzuordnung ("Importdefinition 3") existiert in dieser Installation
bereits und wird **nicht** verändert — das Script erzeugt XML, das exakt
zu dieser Definition passt (Tags wie `id`, `number`, `billing`/`shipping`,
`details/item/articleNumber`, `payment/description`, `dispatch/name`,
Kodierung `iso-8859-1`).

**Bei einer neuen/anderen Faktura-Installation**, in der diese
Importdefinition noch nicht existiert: Die mitgelieferte
`Faktura_Importdefinition.xml` unter *Einstellungen → Importdefinitionen*
als neue Definition laden. Das Mapping (z. B. welches Feld in welches
Freifeld geschrieben wird) ist von Amicron für die eigene Faktura-Version
vorgesehen und muss ggf. je nach individuellem Faktura-Setup angepasst
werden.

Einzustellen ist nur, **woher** Faktura die Dateien liest:

1. Menü **Extras → Datenimport → Aufträge (Datei)**
2. Bei **Importdefinition**: Option **"Aus den Importdefinitionen"**
   wählen, dort **"Importdefinition 3"**
3. Bei **XML-Ordner**: `C:\SRFakturaImport\amicron\import` (der lokale
   Ordner, in den das Script schreibt, siehe Abschnitt "Ordnerstruktur")
4. Bei **"Nach Import"**: aktuell produktiv auf **"Importierte Dateien in
   folgenden Ordner verschieben"** mit demselben Pfad eingestellt (siehe
   Screenshot unten). Empfehlenswert wäre stattdessen ein separater
   `\erledigt`-Unterordner (`C:\SRFakturaImport\amicron\import\erledigt`),
   damit importierte und neue Dateien nicht im selben Ordner landen — das
   Setup-Script legt diesen Unterordner bereits vorsorglich an, er muss
   in Faktura nur noch ausgewählt werden

![Importierte Aufträge in Faktura](docs/faktura_importierte_auftraege.png)

![XML-Import-Dialog in Faktura](docs/faktura_xml_import_dialog.png)

## 3. Installation des Tools (was die `.bat`-Datei macht)

Voraussetzung: der komplette Projektordner (diese Datei,
`import_orders.py`, `import_orders.ico`, `config.ini.example`,
`Faktura_Importdefinition.xml`, `VERSION`, `SRFakturaImport_Setup.ps1`,
`SRFakturaImport_Setup.bat`) liegt bereits auf dem Ziel-PC, z. B. unter
`C:\SRFakturaImport\scripts\shopware-amicron-import\`.

Doppelklick auf **`SRFakturaImport_Setup.bat`** startet
`SRFakturaImport_Setup.ps1` und führt automatisch aus:

1. **Python prüfen/installieren** — falls `python` nicht gefunden wird,
   Installation über `winget install --id Python.Python.3.12`; falls
   winget nicht verfügbar ist, Fallback auf Direkt-Download des
   offiziellen Installers von python.org. Der PATH wird danach in der
   laufenden Sitzung aus der Registry neu geladen, ein Neustart der
   Konsole ist nicht nötig.
2. **Bibliothek installieren** — `pip install requests`
3. **Ordnerstruktur anlegen** — `C:\SRFakturaImport\amicron\import\erledigt`
   (fester Pfad, unabhängig davon, wo der Script-Ordner selbst liegt)
4. **`config.ini` vorbereiten** — falls noch keine vorhanden ist, wird
   sie aus `config.ini.example` erzeugt, wobei der `import_folder`-Pfad
   automatisch korrekt (absolut) eingetragen wird. `shop_url`,
   `client_id`, `client_secret` müssen danach von Hand ergänzt werden.
5. **Desktop-Verknüpfung anlegen** — `Shopware Bestellimport (vX.Y.Z).lnk`
   mit `import_orders.ico` als Icon, Ziel ist `import_orders.py`. Die
   Versionsnummer kommt aus der `VERSION`-Datei und steht damit direkt
   als Text unter dem Desktop-Icon — so ist auf einen Blick erkennbar,
   ob die aktuelle Version installiert ist. Beim erneuten Ausführen des
   Setups wird eine ältere/anders benannte Verknüpfung automatisch
   entfernt, damit nicht mehrere Icons parallel auf dem Desktop liegen.

Eine Neuinstallation (neuer PC, frisches Windows) bedeutet danach nur
noch: Ordner kopieren, `.bat` doppelklicken, `config.ini` mit den drei
Shopware-Werten befüllen — fertig. Ein **Update** auf eine neue Version
läuft genauso: Dateien überschreiben (inkl. der neuen `VERSION`-Datei),
`.bat` erneut ausführen — die Desktop-Verknüpfung wird automatisch mit
der neuen Versionsnummer neu angelegt.

## 4. Ordnerstruktur

Der Script-/Programmordner und der Import-Ordner sind zwei getrennte,
feste Pfade:

```
C:\SRFakturaImport\scripts\shopware-amicron-import\   (Programmordner, Ort beliebig waehlbar)
├── import_orders.py
├── import_orders.ico
├── config.ini                  (enthält Zugangsdaten, nicht versionieren!)
├── config.ini.example
├── Faktura_Importdefinition.xml
├── SRFakturaImport_Setup.ps1
├── SRFakturaImport_Setup.bat
└── README.md

C:\SRFakturaImport\amicron\import\    (fester Pfad, in Faktura als XML-Ordner hinterlegt)
├── shopware_orders_*.xml       (vom Script erzeugte Dateien)
└── erledigt\                   (optionaler Zielordner fuer "Nach Import verschieben")
```

`import_folder` in `config.ini` muss exakt auf `C:\SRFakturaImport\amicron\import`
zeigen — dieser Pfad ist unabhängig davon, wo der Programmordner selbst liegt.

## 5. `config.ini` — Felder erklärt

```ini
[shopware]
shop_url = https://www.deinshop.de     ; Shop-URL ohne abschliessenden Slash
client_id = ...                        ; Access-ID der Shopware-Integration
client_secret = ...                    ; Secret-Key der Shopware-Integration
order_state = open                     ; Technischer Name des zu exportierenden Bestellstatus

[faktura]
import_folder = C:\...\import          ; Ordner, den Faktura ueberwacht (absoluter Pfad!)
file_prefix = shopware_orders          ; Dateiname-Praefix, Zeitstempel wird automatisch angehaengt
```

## 6. Individuelle Anpassungen (Stephan-spezifisch)

Diese Regeln sind fest im Script (`import_orders.py`) hinterlegt und für
diesen Anwendungsfall angepasst — bei Wiederverwendung für einen anderen
Shop ggf. überprüfen/ändern:

- **Bestellnummer-Feld**: enthält `Bestellnummer - Verkaufskanal`
  (z. B. `100551 - Sicherungsstangen.de`), da über einen Shop zwei
  Verkaufskanäle (Sicherungsstangen.de, Mörtelspritzen.de) laufen
- **Artikelname**: bei Varianten-Produkten (z. B. Sicherungsstangen mit
  Auswahl von Größe/Farbe) werden die vom Kunden gewählten Optionen aus
  `payload.options` an den Artikelnamen angehängt, z. B.
  `ADE Sicherungsstange (Größe: für Laibungsbreite 39-51 cm, Farbe: Weiß - ähnlich RAL 9016 Verkehrsweiß)`
  — sonst würde in Faktura nur die reine Produktbezeichnung ohne die
  Kundenauswahl ankommen. Die Optionsgruppe **"Lieferung nach"** wird
  dabei bewusst ausgeschlossen (steht in `OPTION_GROUPS_EXCLUDED_FROM_ARTICLE_NAME`
  in `import_orders.py`), da sie nur die Versandländer-Auswahl ist, kein
  Produktmerkmal
- **Länderkürzel ("L"-Feld)**: Shopware liefert 2-stellige ISO-Codes
  (`DE`, `AT`, ...), die unverändert übertragen werden. Das passt exakt
  zur "Landeskürzel"-Spalte in Faktura's Länder-Stammdaten
  (*Einstellungen → Länderauswahl*), wo z. B. Österreich als `AT`
  geführt wird — die `CONVERTLAND`-Tabelle in der alten
  Shopware-V4.1-Importdefinition (mit Kurzcodes wie `A`/`D`) ist dafür
  nicht (mehr) maßgeblich.
- **Lieferart**: wird immer fest als `Paketdienst` übertragen, unabhängig
  von der in Shopware hinterlegten Versandart
- **Bestelldatum**: Format `TT.MM.JJJJ` (deutsches Datumsformat)
- **Versandkosten-Artikel**: Line-Items mit "Versandkosten" im Namen
  bekommen automatisch die feste Faktura-Artikelnummer `1000154`
  zugewiesen, unabhängig von der Shopware-Artikelnummer
- **E-Mail-Adresse**: wird innerhalb des `billing`/`KUNADRESSE`-Blocks
  übertragen (nicht als eigenständiges Tag) — das war nötig, damit
  Faktura die Adresse korrekt dem neu angelegten Kundendatensatz
  zuordnet (siehe Troubleshooting)

## Troubleshooting / bekannte Stolperfallen

- **`Accept: application/json` fehlt** → Shopware liefert Bestelldaten
  sonst im JSON:API-Format (verschachtelt unter `attributes`), das
  Script erwartet aber das flache Format. Ohne diesen Header sind alle
  Felder leer.
- **Backslash nach Laufwerksbuchstabe** → `import_folder = c:Pfad\...`
  (ohne `\` direkt nach dem Doppelpunkt) ist unter Windows KEIN
  absoluter Pfad, sondern "relativ zum aktuellen Verzeichnis auf
  Laufwerk C:". Führt zu falsch platzierten Dateien ohne Fehlermeldung.
  Immer `C:\Pfad\...` mit Backslash direkt nach dem Doppelpunkt
  verwenden.
- **winget-Paket-ID Groß-/Kleinschreibung** → die korrekte ID ist
  `Python.Python.3.12` (großes P in der Mitte), nicht `Python.python.3.12`.
- **Netzlaufwerke in Faktura nicht sichtbar** → falls Faktura auf einem
  Server läuft und über RDP bedient wird: gemappte Netzlaufwerke sind
  nur in der Windows-Sitzung sichtbar, in der sie erstellt wurden;
  UAC-Elevation (z. B. "Als Administrator ausführen") kann das Laufwerk
  "verstecken". Betrifft diese Installation nicht mehr, da das Script
  jetzt lokal auf dem Faktura-PC läuft, ist aber relevant, falls das
  Tool auf einem Server-Setup wiederverwendet wird.
- **E-Mail-Adresse zeigt Shop-Domain statt Kunden-E-Mail** → trat auf,
  solange `<email>` als eigenständiges Tag außerhalb des
  `<billing NewData="KUNADRESSE">`-Blocks stand. Fix: `<email>` wurde in
  den `billing`-Block verschoben (bestätigt durch Vergleich mit der für
  HaBeFa.de funktionierenden Importdefinition, die `EMAIL` ebenfalls
  innerhalb der `CUSTOMERS_ADDRESS`/`KUNADRESSE`-Gruppe verschachtelt).

## Änderungsprotokoll

### 1.3.0 (2026-08-06)
- Zentrale `VERSION`-Datei als Versionsquelle eingeführt
- Desktop-Verknüpfung enthält jetzt die Versionsnummer im Dateinamen
  (`Shopware Bestellimport (vX.Y.Z).lnk`), damit sie direkt unter dem
  Icon sichtbar ist
- Setup-Script entfernt beim erneuten Ausführen automatisch ältere/
  anders benannte Verknüpfungen, um Duplikate zu vermeiden

### 1.2.1 (2026-08-06)
- Länderkürzel-Fix aus 1.1.0 korrigiert: Es wird wieder der reine,
  unveränderte 2-stellige ISO-Code (`DE`, `AT`, ...) übertragen — das
  entspricht Faktura's tatsächlicher Länder-Stammdatentabelle, die
  vorherige Umschreibung auf `AUT` war ein Irrtum

### 1.2.0 (2026-08-06)
- Konsolenfenster schließt sich nach dem Lauf nicht mehr automatisch
  (auch bei Fehlern) — es bleibt offen mit einer Meldung, bis manuell
  mit Enter geschlossen wird
- Klarere Meldung bei keinen offenen Bestellungen: "Es sind keine neuen
  Bestellungen eingegangen!"

### 1.1.0 (2026-08-06)
- Artikelname enthält jetzt die vom Kunden gewählten Varianten-Optionen
  (z. B. Größe, Farbe), nicht mehr nur die reine Produktbezeichnung
  (Option "Lieferung nach" bewusst ausgeschlossen)
- Länderkürzel wird als 3-stelliger ISO-Code (`DEU`/`AUT`) übertragen,
  damit Faktura's `CONVERTLAND`-Tabelle auch Österreich korrekt erkennt

### 1.0.0 (2026-08-06)
- Erste vollständige, produktiv getestete Version
- OAuth2-Anbindung an Shopware-6.7-Admin-API, Export offener Bestellungen
- XML-Erzeugung passend zur bestehenden Amicron-Importdefinition 3
- Verkaufskanal wird in die Bestellnummer eingetragen
- Lieferart fest auf "Paketdienst", Datumsformat TT.MM.JJJJ
- Versandkosten-Artikel wird auf feste Faktura-Artikelnummer 1000154 gemappt
- E-Mail-Zuordnungsfehler behoben (Tag in `billing`-Block verschoben)
- Automatisiertes Setup per `SRFakturaImport_Setup.bat`
  (Python-Installation, Ordnerstruktur, `config.ini`, Desktop-Icon)
