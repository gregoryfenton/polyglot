# Hexscope

Hexscope is a lightweight, high-performance binary hex viewer built as a dual-target binary polyglot. From a single, identical file (`hexscope.com`), it executes natively as a **16-bit DOS COM program** on legacy hardware or DOS emulators like DOSBox and 86Box, and as a **64-bit Linux ELF executable** on modern UNIX environments.

Designed with a first-principles, pragmatic engineering approach, Hexscope avoids heavy abstractions, relying entirely on raw assembly, direct video memory manipulation (for DOS), and optimized ANSI terminal controls (for Linux).

---

## What is a Binary Polyglot?

A binary polyglot is a single file that satisfies the execution requirements of multiple distinct operating systems or architectures simultaneously. 

Hexscope achieves this by carefully overlaying binary structures:
1. **The ELF Header Overlap**: The beginning of the file contains a valid 64-bit ELF header (`0x7F "ELF"`), complete with program headers pointing to the Linux entry point.
2. **The DOS Execution Stub**: Buried safely within the header offsets, a short jump instruction (`jmp dos_start`) diverts DOS execution past the Linux structures directly into the real-mode 16-bit payload. 

Neither operating system gets confused by the foreign headers present in its address space - each parser extracts only the sections relevant to its own runtime environment.

---

## Features

* **Dual Platform Native**: Runs without modification on MS-DOS 6.22 (and compatible DOS environments) and 64-bit Linux distributions (tested on Ubuntu 24.04 LTS).
* **Interactive Navigation**: Seamlessly scroll through files using arrow keys, Page Up / Page Down, and Home / End shortcuts.
* **Comprehensive Byte Inspection**: Displays live status information for the selected byte, including its hexadecimal offset, hex value, decimal value, 8-bit binary representation, and total file size.
* **Read-Only Safety**: Strictly read-only file inspection designed to prevent accidental data corruption.
* **Polyglot Build Automation**: Includes a single unified build script that functions natively in both Windows Command Prompt (`cmd.exe`) and Linux Bash.

---

## Keyboard Controls & Shortcuts

| Key | Action |
| :--- | :--- |
| **Left / Right Arrows** | Move selection to the previous or next individual byte. |
| **Up / Down Arrows** | Move selection up or down by a full row (16 bytes). |
| **Home** | Jump to the beginning of the current 256-byte page. |
| **End** | Jump to the very last byte of the file. |
| **Page Up / Page Down** | Scroll through the file in 256-byte page increments. |
| **Q / ESC** | Quit and exit the application, restoring terminal settings or video modes. |

---

## Project Structure

```text
├── hexscope.asm     # Core assembly source code (MASM / NASM compatible syntax)
├── build.bat        # Unified polyglot build script (runs on Windows and Linux Bash)
└── README.md        # Project documentation
```

---

## Prerequisites

To assemble and build Hexscope from source, you will need:
* **NASM** (Netwide Assembler) installed and available in your system path.
* A target environment for testing (e.g., **86Box**, **DOSBox**, or a Linux terminal).

---

## Building the Project

Hexscope features a unified polyglot build script (`build.bat`) that works seamlessly across platforms without needing separate Makefiles or batch files.

### On Linux
Open your terminal in the source directory and run:
```bash
bash build.bat
```
*(The script will automatically assemble the binary using NASM and apply executable permissions via `chmod +x`).*

### On DOS
Switch to the source directory and run:
```dos
build.bat
```

---

## Running Hexscope

### In Linux
Pass any target file as a command line argument:
```bash
./hexscope.com hexscope.com
```

### In DOS / 86Box
Boot your DOS environment and execute the compiled binary with a filename argument:
```dos
HEXSCOPE.COM RUNME.COM
```

---

## Technical Architecture

* **DOS Mode**: Bypasses standard I/O bottlenecks by writing directly to video memory segment `0xB800` using direct character and attribute word writes, combined with standard DOS INT 21h file handles and INT 16h keyboard polling.
* **Linux Mode**: Configures terminal attributes via `termios` system calls to enable raw input mode (disabling canonical buffering and local echo), renders output via standard Linux `sys_write` syscalls, and positions the cursor precisely using ANSI escape sequences.
