## Widewine Installer
I also made a Widevine Installer Script for chromium (works for helium too) that essentially works the same way as chromium-widewine aur package and installs to /usr/lib/chromium/WidevineCdm
It should technically run on any linux-distribution with bash

READ THE SCRIPT BEFORE RUNNING (NEVER trust a random script on the internet)

```sh
curl -fsSL https://raw.githubusercontent.com/cryptic-noodle/configs/main/helium/widevine-chromium-installer.sh | sudo bash
```
or
```sh
wget -qO- https://raw.githubusercontent.com/cryptic-noodle/configs/main/helium/widevine-chromium-installer.sh | sudo bash
```
If you run it again after installation it will give option to uninstall, or just run with --uninstall
