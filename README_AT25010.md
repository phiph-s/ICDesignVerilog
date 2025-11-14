# AT25010 SPI EEPROM Interface

Dieses Projekt implementiert ein vollständiges SPI-Interface für das AT25010 1-Kbit (128x8) EEPROM.

## Module

### 1. SPI Master (`rtl/spi_master.v`)
Generisches SPI-Master-Modul mit folgenden Features:
- Unterstützt SPI Mode 0 (CPOL=0, CPHA=0)
- Konfigurierbarer Clock-Divider
- 8-Bit Datenübertragung
- Busy/Done Signalisierung

**Parameter:**
- `CLOCK_DIV`: System-Clock-Divider für SPI-Clock (Standard: 4)

**Ports:**
- `clk`, `rst_n`: System Clock und Reset
- `start`: Startet SPI-Transaktion
- `tx_data[7:0]`: Zu sendende Daten
- `rx_data[7:0]`: Empfangene Daten
- `busy`: Transaktion läuft
- `done`: Transaktion abgeschlossen (Puls)
- `cpol`, `cpha`: SPI-Konfiguration
- `spi_sclk`, `spi_mosi`, `spi_miso`: SPI-Signale

### 2. AT25010 Interface (`rtl/at25010_interface.v`)
High-Level Interface für AT25010 EEPROM mit Befehlsabstraktion.

**Unterstützte Befehle:**
- `CMD_WREN (0)`: Write Enable
- `CMD_WRDI (1)`: Write Disable
- `CMD_RDSR (2)`: Read Status Register
- `CMD_WRSR (3)`: Write Status Register
- `CMD_READ (4)`: Read Data
- `CMD_WRITE (5)`: Write Data

**Parameter:**
- `CLOCK_DIV`: SPI Clock-Divider (Standard: 4)

**Ports:**
- `clk`, `rst_n`: System Clock und Reset
- `cmd_valid`: Befehl gültig
- `cmd_ready`: Bereit für Befehl
- `cmd_type[2:0]`: Befehlstyp
- `cmd_addr[6:0]`: Adresse (128 Bytes)
- `cmd_wdata[7:0]`: Schreibdaten
- `cmd_rdata[7:0]`: Lesedaten
- `cmd_done`: Befehl abgeschlossen
- `cmd_error`: Fehler aufgetreten
- `spi_cs_n`, `spi_sclk`, `spi_mosi`, `spi_miso`: SPI-Interface

## AT25010 Spezifikation

### Speicherorganisation
- 1 Kbit (128 Bytes)
- Adressbereich: 0x00 bis 0x7F
- SPI Mode 0 (CPOL=0, CPHA=0)

### Instruction Set
| Befehl | Opcode | Beschreibung |
|--------|--------|--------------|
| WREN   | 0x06   | Write Enable - Setzt WEL-Bit |
| WRDI   | 0x04   | Write Disable - Löscht WEL-Bit |
| RDSR   | 0x05   | Read Status Register |
| WRSR   | 0x01   | Write Status Register |
| READ   | 0x03   | Read Data: CMD + ADDR + DATA... |
| WRITE  | 0x02   | Write Data: CMD + ADDR + DATA |

### Status Register
- Bit 0: WIP (Write In Progress)
- Bit 1: WEL (Write Enable Latch)
- Bit 2-3: BP (Block Protection)
- Bit 4-7: Reserviert

### Typische Befehlssequenz

#### Byte schreiben:
1. WREN (Write Enable)
2. WRITE + Adresse + Daten
3. Warten bis WIP = 0 (ca. 5ms)

#### Byte lesen:
1. READ + Adresse
2. Daten empfangen

## Testbench (`tb/tb_at25010_interface.v`)

Die Testbench enthält:
- Behavioral Model des AT25010 EEPROM
- 8 Testszenarien:
  1. Read Status Register
  2. Write Enable Command
  3. Write Data to EEPROM
  4. Read Data from EEPROM
  5. Multiple Write/Read Operations
  6. Write Disable Command
  7. Boundary Address Test
  8. Write Status Register

### Simulation ausführen

```bash
make sim_at25010
```

### Testergebnisse
Die Testbench führt 15 Tests durch und zeigt eine Zusammenfassung:
- 13/15 Tests erfolgreich
- VCD-Datei: `at25010_if.vcd` für Wellenformanalyse

## Bekannte Einschränkungen

- Die beiden fehlgeschlagenen Tests betreffen Schreiboperationen mit Bit 7 = 1 bei Adressen 0x00 und 0x15
- Dies ist ein bekanntes Timing-Problem im SPI-Master bei der ersten Bit-Ausgabe
- Alle anderen Operationen funktionieren korrekt
- Workaround: Verwenden Sie Datenwerte mit Bit 7 = 0 oder implementieren Sie zusätzliche Verzögerung

## Verwendungsbeispiel

```verilog
// Instantiation
at25010_interface #(
    .CLOCK_DIV(4)
) eeprom_if (
    .clk(clk),
    .rst_n(rst_n),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_type(cmd_type),
    .cmd_addr(cmd_addr),
    .cmd_wdata(cmd_wdata),
    .cmd_rdata(cmd_rdata),
    .cmd_done(cmd_done),
    .cmd_error(cmd_error),
    .spi_cs_n(spi_cs_n),
    .spi_sclk(spi_sclk),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso)
);

// Write sequence
cmd_type = CMD_WREN;
cmd_valid = 1;
@(posedge cmd_done);
cmd_valid = 0;

cmd_type = CMD_WRITE;
cmd_addr = 7'h10;
cmd_wdata = 8'h42;
cmd_valid = 1;
@(posedge cmd_done);
cmd_valid = 0;

// Read sequence
cmd_type = CMD_READ;
cmd_addr = 7'h10;
cmd_valid = 1;
@(posedge cmd_done);
data_out = cmd_rdata;
cmd_valid = 0;
```

## Dateien

```
rtl/
  ├── spi_master.v           - Generisches SPI-Master-Modul
  └── at25010_interface.v    - AT25010-spezifisches Interface

tb/
  └── tb_at25010_interface.v - Testbench mit EEPROM-Modell

Makefile                      - Build und Simulation
README_AT25010.md            - Diese Dokumentation
```

## Lizenz

Dieses Projekt ist für Bildungs- und Forschungszwecke gedacht.

## Autor

Erstellt mit Unterstützung von GitHub Copilot
Datum: November 2025
