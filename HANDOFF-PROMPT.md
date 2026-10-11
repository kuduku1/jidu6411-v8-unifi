# Hand-off prompt (paste this to the next assistant together with the zip)

I am continuing an OpenWrt firmware project. The attached zip `jidu6411-v8-buildkit.zip` is a complete GitHub-Actions build kit; read its `README.md` first — it describes exactly what is in it, what has been verified and what has not. Do not redesign it; finish and test it.

**Hardware / network context**
- Router: JioRouter AX6000 **JIDU6J11-6411** (Qualcomm IPQ9554/IPQ9574 family, 512 MB RAM, NAND with UBI partition `ubi`; 2.4 GHz = IPQ9574 internal radio (ath11k AHB), 5 GHz = QCN9074 (ath11k PCI)). Currently runs my v7 image: OpenWrt SNAPSHOT r35553+327-fdb162fb81 (Sandiep's private build, kernel 6.18.44), board name `jiorouter,ax6000-jidu6j11`.
- Network: UniFi Cloud Gateway Ultra 10.0.0.1, TP-Link TL-SG1218MPE switch, Grandstream GWN7665/GWN7604 APs. SSID `trojan` = VLAN 10 (WPA3), `trojan_2` = VLAN 50 (2.4 GHz IoT), CCTV VLAN 100. Jio 100 Mbps.
- This IDU (MAC 28:a9:15:8f:48:83) is a UniFi-adopted wired AP via openUF at **10.0.0.8**; a second 6411 will be 10.0.0.10. One more 6411 gets the **stock** image (no UniFi).
- Hard requirements: WiFi country **PA** (never IN), **160 MHz** on 5 GHz (works on ch 100 under PA), LuCI HTTPS only, ubnt bootstrap account locked after adoption, default root password kept (I change it myself), v8 must install over v7 with a normal sysupgrade and keep the `ubi` volume layout.

**What to do next**
1. Push the kit to my GitHub repo `kuduku1/jidu6411-v8-unifi` and run the workflow (variant `both`). Fix build failures without changing the design (keep the mac80211 6.18.39 pin and the board-data package).
2. Download the artifacts, verify: kernel 6.18.55; sysupgrade metadata `supported_devices` contains both `jiorouter,ax6000-jidu6j11-6411` and `jiorouter,ax6000-jidu6j11`; image contains `/lib/firmware/ath11k/{IPQ9574,QCN9074}/hw1.0/board-2.bin` with the SHA-256 listed in README; `/etc/uci-defaults/90-v8-hardening`; for unifi also `/usr/share/openuf-src`, `/etc/config/openuf` (ng htmode_floor HE20), lua deps, kmod-nft-bridge, kmod-sched-act-police.
3. Security-audit the images (no unexpected accounts, authorized_keys, host keys, cron jobs, network calls; compare openUF source with github.com/yesrab/openUF @78418aef — only our 2 patches may differ).
4. Guide me through the canary flash (stock first, on the non-UniFi 6411), then the UniFi one, using the README checklist. Keep v7 as rollback; recovery is via UART.
