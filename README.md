# NetWorker

NetWorker ist ein installationsfreies PowerShell-Netzwerktool fuer Windows 11. Es wird per `git clone` gestartet und bietet ein farbiges Terminal-Menue, das per Zahl navigiert wird.

## Starten

```powershell
git clone https://github.com/GotUrBack-Public/NetWorker.git
cd NetWorker
.\networker.cmd
```

Alternativ direkt mit PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\NetWorker.ps1
```

## Funktionen

1. Netzwerk scannen
2. Ping-Test
3. Geraete im Netzwerk zaehlen
4. Einfachen Geschwindigkeitstest ausfuehren
5. Netzwerk-Uebersicht mit IP, Gateway, Subnetz und aktiven Adaptern
6. Hilfe
0. Beenden

## Hinweise

- Keine Installation und keine externen Module noetig.
- Der Scan prueft das lokale IPv4-Subnetz per ICMP-Ping.
- Fuer den Speedtest wird eine kleine Datei von einer oeffentlichen URL geladen; das Ergebnis ist eine einfache Naeherung.
- Windows-Firewall oder Netzwerkrichtlinien koennen Ping-Ergebnisse beeinflussen.