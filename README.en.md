# 📺 TVBox Project – IFSP Salto | Multitool Fork

[![Shell Script](https://img.shields.io/badge/Shell_Script-Bash-2E7D32?logo=gnu-bash&logoColor=white&style=flat-square)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-1.0.0-1565C0?style=flat-square)](https://github.com/projetotvbox/multitool/releases)
[![views](https://hits.sh/github.com/projetotvbox/multitool.svg?style=flat-square&label=views&color=0A66C2)](https://hits.sh/github.com/projetotvbox/multitool/)

> **Language / Idioma:** **[🟢 English]** | [Português](README.md)

## 🏫 About the Project

The **TVBox Project – IFSP Salto** is a community outreach initiative from the [Instituto Federal de São Paulo, Salto Campus](https://slt.ifsp.edu.br), which receives TV boxes seized by the Brazilian Federal Revenue Service and repurposes them as tools for digital inclusion.

The process involves the **complete de-characterization** of the devices — removal of the proprietary system and installation of Linux distributions adapted for ARM architecture — followed by donation to public schools in underprivileged regions, expanding access to technology for the communities that need it most.

Beyond de-characterization, the project retains a portion of the devices for internal use in research, development and experimentation, producing tools, custom operating systems and open technical documentation for the broader community.

---

## 💡 Motivation for this Fork

The [original Multitool](https://github.com/paolosabatino/multitool), developed by Paolo Sabatino, is the base tool used in the de-characterization process. This fork was born out of two main needs:

**1. Build process improvements (`create_image.sh`)**
- Interactive TUI interface using `dialog` instead of plain text output
- Board configuration selection via menu, automatically populated from `.conf` files
- Structured logging system with stage markers, command output capture and automatic log rotation
- Automatic resource management via `trap`, ensuring loop devices and mount points are always released on failure
- **Embedded image support**: allows selecting a `.gz` at build time to include it directly in the generated image's backup folder, eliminating manual post-flash copy steps

**2. Features aimed at mass de-characterization (`multitool.sh`)**
- **Auto-restore**: allows configuring a backup file to be automatically restored on the next boot, with no human interaction — ideal for batch operations
- **Adaptive integrity verification**: when setting up auto-restore, the system generates and stores checksum metadata (full SHA256 for small files, head/mid/tail samples for large files), automatically verified before each restore
- **Automatic device selection**: if only one eMMC is available, the restore starts without prompting; if more than one is detected, the technician chooses manually to prevent accidental writes

---

## 🔧 What is Multitool?

Multitool is a minimal Linux system that runs directly from an SD card, designed for TV boxes based on Rockchip chips. It boots before the box's internal system and provides an interactive menu for low-level operations on the device's eMMC memory.

### Menu options

| Option | Description |
|--------|-------------|
| Backup flash | Creates a compressed (`.gz`) backup of the eMMC to the MULTITOOL partition |
| Restore flash | Restores an existing backup to the eMMC |
| Erase flash | Wipes the eMMC contents |
| Drop to Bash shell | Opens an interactive shell for manual operations |
| Burn image to flash | Writes an image directly to eMMC (supports `.gz`, `.zip`, `.7z`, `.tar`, `.img`) |
| Configure auto restore | Sets which backup will be automatically restored on next boot |
| Show Current Auto-Restore | Displays details of the current auto-restore configuration |
| Install Jump start on NAND | Installs alternative bootloader on NAND devices (rknand only) |
| Install Armbian via steP-nand | Installs Armbian directly on NAND via steP-nand (rknand only) |
| Change DDR Command Rate | Adjusts DDR timing for rk322x devices with stability issues |
| Reboot / Shutdown | Reboots or shuts down the device |

---

## 🚀 Building the image

### Prerequisites

Debian-based system. Install the required packages:

```sh
sudo apt install multistrap squashfs-tools parted dosfstools ntfs-3g dialog zenity
```

Clone the repository:

```sh
git clone https://github.com/projetotvbox/multitool
cd multitool
```

### Building

```sh
sudo ./create_image.sh
```

The script will present:

1. **Board configuration selection** — interactive menu populated from the available `sources/*.conf` files
2. **Embedded image (optional)** — allows selecting a `.gz` to include directly in the generated image's backup folder
3. **Auto-restore (optional)** — if an embedded image is selected, asks whether to enable it so the restore happens automatically on first boot

The final image is generated at `dist-$board/multitool.img`.

> ⚠️ The script requires root permissions, as it needs to manipulate loop devices.

> 📝 Build logs are saved to `logs/` and automatically rotated, keeping the 10 most recent.

### Writing the image to the SD card

```sh
sudo dd if=dist-$board/multitool.img of=/dev/sdX bs=4M conv=sync,fsync
```

Replace `/dev/sdX` with your SD card device.

Alternatively, use [Balena Etcher](https://etcher.balena.io/) to flash the image with a graphical interface, available for Windows, macOS and Linux.

---

## 📋 Using Multitool on the box

### Boot

Insert the SD card into the TV box and power it on. The system will automatically boot from the card and present the Multitool main menu.

> 💡 Depending on the box model, you may need to press a recovery button during startup to force booting from the SD card.

### Batch de-characterization workflow

The recommended flow for mass operations with pre-configured auto-restore:

1. Build the image with an embedded backup image and auto-restore enabled
2. Flash the image to the SD card
3. Insert the SD into the box and power on
4. Multitool detects the auto-restore configuration, displays a 10-second countdown and starts the restore automatically
5. When done, it offers the option to shut down immediately or wait — by default, it shuts down after 10 seconds
6. Remove the SD card; the device is ready

### Configuring auto-restore manually

If the image was not built with auto-restore, it can be configured through the menu:

1. Copy the `.gz` backup file to the `backups/` folder on the MULTITOOL partition
2. From the menu, select **"Configure auto restore file image"**
3. Select the desired file
4. The system will calculate the integrity checksum and save the configuration
5. The next time the box is powered on with the SD card inserted, the restore will happen automatically

---

## 🔗 References

- [Original repository — Paolo Sabatino](https://github.com/paolosabatino/multitool)
- [Instituto Federal de São Paulo — Salto Campus](https://slt.ifsp.edu.br)

---

Made with 🐧 at IFSP Salto · Technology in service of public education