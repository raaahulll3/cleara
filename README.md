# Cleara 🚀

**Cleara v1** – Advanced & Safe Linux Cleanup Tool  

~ Reclaim disk space and keep your Linux system clean ~ 

## Features
- Drop system cache
- Clean `/tmp`
- Clean package cache (apt, dnf, pacman, zypper)
- Purge old configs
- Clean user/global cache
- Interactive menu or CLI options
- Dry-run mode for safe preview

## Installation

```bash
git clone https://github.com/raaahulll3/cleara.git
cd cleara
chmod +x cleara.sh
```
## Usage
Interactive mode

```
./cleara.sh
```
CLI options

```
./cleara.sh --all       # Full cleanup
./cleara.sh --tmp       # Clean /tmp
./cleara.sh --cache     # Clean caches
./cleara.sh --pkg       # Clean package cache
./cleara.sh --purge     # Purge old configs
./cleara.sh --dry-run   # Preview actions without deleting
./cleara.sh --quiet     # Minimal output
./cleara.sh --no-color  # Disable colors
./cleara.sh -v          # Version info
./cleara.sh -h          # Help
```
