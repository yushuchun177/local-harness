# Local-Harness. Benutzerhandbuch

> **Dieses Programm enthält keine GGUF-Modellgewichte.** Das Modell muss selbst heruntergeladen und importiert werden.

Local-Harness ist eine grafische Hülle (Harness) für llama.cpp: Modell laden, Parameter einstellen und mehrzügige Unterhaltungen in einem Fenster – ohne Kommandozeile.

---

## 1. Installation und Start

1. Release herunterladen (portables ZIP oder einzelne EXE) und in einen beliebigen Ordner entpacken (Umlaute im Pfad sind unproblematisch).
2. `local-harness.exe` starten.
3. Beim ersten Start wird das Modell geladen; in der Mitte erscheint einige Sekunden lang eine Ladeanzeige.
4. Danach die Frage unten eingeben und Enter drücken.

Ordnerstruktur:

```
local-harness.exe      Hauptprogramm
_internal\             Laufzeitbibliotheken (nicht löschen oder umbenennen)
llama\                 llama.cpp-Dateien (llama-cli.exe und abhängige DLLs)
model\                 eigene .gguf-Modelle
chats\                 Unterhaltungsverlauf (wird beim ersten Start angelegt)
config.json            Oberflächen- und Parametereinstellungen (beim ersten Start angelegt)
```

## 2. Modell vorbereiten

Es ist kein Modell enthalten. Laden Sie eine GGUF-Datei (Endung `.gguf`) herunter, etwa eine quantisierte Version von Hugging Face oder ModelScope.

Zwei Wege zum Import:

- **In den Ordner kopieren**: die `.gguf` nach `model\` legen, Programm neu starten, dann erscheint sie in der Modellliste.
- **Über die Oberfläche importieren**: oben auf „Importieren“ klicken und einen Ordner mit Modellen wählen; der Pfad wird gemerkt.

Hinweise:

- Bei geteilten Modellen genügt der erste Teil (`xxx-00001-of-00002.gguf`); die übrigen Teile im selben Ordner belassen.
- mmproj-Dateien, Vision-Projektoren, Embedding- und Reranker-Modelle sowie Dateien unter 20 MB werden automatisch ignoriert.
- Modellgewichte unterliegen der Lizenz ihrer Herausgeber (Qwen z. B. Apache-2.0). Bitte die jeweilige Lizenz beachten.

Speicherbedarf:

| Modellgröße | Dateigröße (Richtwert) | Empfohlener RAM |
| --- | --- | --- |
| 0,4B – 1B | 300 MB – 900 MB | ab 4 GB |
| 1,5B – 2B | 1 GB – 2 GB | 8 GB |
| 3B – 4B | 2 GB – 3 GB | 16 GB |

## 3. Oberfläche

- **Obere Leiste**: Modellauswahl, „Importieren“, Parameter (Temperatur / Kontext / Antwortlimit), Denkmodus, „Über“, „Einstellungen“, Theme-Umschaltung.
- **Linke Leiste**: Unterhaltungsliste. Beim Überfahren erscheint Löschen, Rechtsklick zum Umbenennen oder Löschen.
- **Mitte**: Nachrichtenbereich, Antworten erscheinen als Stream.
- **Unten**: Eingabefeld und „Senden“, während der Generierung „Stopp“.
- **Statuszeile**: links Modell, Kontextauslastung und natives Limit des Modells; rechts der Token-Anteil dieser Unterhaltung.

## 4. Parameter

| Parameter | Bereich | Bedeutung |
| --- | --- | --- |
| Temperatur | 0 – 2 | Niedriger = stabiler, höher = kreativer. Code 0,2–0,6, Fragen 0,7, Texte 0,9–1,2 |
| Kontext | 512 – natives Limit des Modells | Token, die eine Unterhaltung behält. Das Slider-Maximum stammt vom Modell; die Statuszeile zeigt „native xxxx“ |
| Antwortlimit | 64 – 8192 | Maximale Token pro Antwort. Bei abgeschnittenen Antworten erhöhen |
| Denkmodus | an / aus | Für Modelle mit Denkschritt (z. B. Qwen3): erst denken, dann antworten; der Denkprozess erscheint nicht in der Antwort |

Werte lassen sich direkt eingeben oder per Slider ändern; sie wirken sofort und werden in `config.json` gespeichert.

## 5. Kontextkomprimierung

Lange Unterhaltungen überschreiten irgendwann das Kontextfenster. Bei aktiver automatischer Komprimierung wird die ältere Historie vor der nächsten Frage zu einer Zusammenfassung verdichtet, sobald der Schwellwert erreicht ist; die letzten Runden bleiben im Wortlaut erhalten.

- Wo: **Einstellungen → Kontextkomprimierung**.
- Der Schwellwert ist in 1024-Token-Schritten einstellbar: **1024 / 2048 / 3072 / 4096**, Standard **2048**.
- Die Anzahl der im Wortlaut behaltenen Runden ist wählbar (Standard 4).
- Die Komprimierung startet kurzzeitig einen Modellprozess und dauert einige Sekunden; währenddessen kann nicht gesendet werden.
- Abschaltbar – dann bei vollem Kontext eine neue Unterhaltung beginnen.

## 6. Tastenkürzel

| Taste | Funktion |
| --- | --- |
| Enter | Senden |
| Umschalt + Enter | Zeilenumbruch |
| Strg + Enter | Senden |
| Esc | Generierung stoppen |
| Strg + L | Eingabefeld leeren |

## 7. Daten und Sicherung

- Unterhaltungen liegen in `chats\`, eine `.json` pro Unterhaltung; Datei löschen = Unterhaltung löschen.
- Oberfläche, Parameter und importierte Modellordner stehen in `config.json`; löschen setzt auf Standard zurück.
- Das Programm greift nicht auf das Netzwerk zu und braucht kein Konto; Inhalte werden nicht übertragen.
- Rechnerwechsel: den gesamten Programmordner inklusive `model\` kopieren.

## 8. Häufige Fragen

**Startet und schließt sich sofort**
Vermutlich wurde `_internal\` oder `llama\` verschoben oder vom Virenscanner blockiert. Release erneut entpacken.

**Meldung, es sei keine Modelldatei vorhanden**
`model\` ist leer. Eine `.gguf` hineinlegen oder „Importieren“ nutzen und neu starten.

**Mein Modell erscheint nicht**
Prüfen: `.gguf`, größer als 20 MB, kein mmproj- oder Embedding-Modell. Bei geteilten Modellen nur der erste Teil.

**Antworten sind langsam**
Kleineres Modell wählen; in den Einstellungen die Threads auf die Anzahl der CPU-Kerne setzen; Notebook am Netzteil betreiben und Energiesparen abschalten.

**Antworten brechen ab**
„Antwortlimit“ erhöhen (z. B. 2048).

**Nach langer Unterhaltung langsam oder Kontextwarnung**
Automatische Komprimierung ist standardmäßig aktiv; Schwellwert in den Einstellungen prüfen oder neue Unterhaltung starten.

**Modellname erscheint als „Qwen3 0.6B · Q8_0“**
Das ist korrekt: Name und Quantisierung werden aus den GGUF-Metadaten gelesen.

## 9. Lizenz

Dieses Projekt steht unter GPLv3. Das Paketieren und Verteilen von Binärdateien ist erlaubt, aber bei jeder Weitergabe des Programms (Quellcode oder Binärdatei) muss der vollständige zugehörige Quellcode mitgeliefert werden; geänderte Versionen müssen ebenfalls quelloffen bleiben.

Modellgewichte sind nicht Teil des Projekts und unterliegen den Lizenzen ihrer Herausgeber.
