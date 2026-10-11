# JioRouter AX6000 JIDU6J11 (6411) — firmware v8

Builds two OpenWrt images for the Jio IDU **JIDU6J11-6411** (also 6111, same board):

| Variant | What it is | Install on |
|---|---|---|
| **v8-unifi** | Wired access point adopted by a UniFi Cloud Gateway (openUF UniFi emulation), Tailscale installed on first boot | the IDU used as a UniFi AP |
| **v8-stock** | Plain OpenWrt router (firewall, DHCP, NAT as normal), same hardening | the other 6411 that does not need UniFi |

## What v8 is built from

* **OpenWrt main** at the commit in `openwrt.pin` (2026-10-11): kernel **6.18.55**, the PPE/EDMA Ethernet RX-DMA fix (e8ca976e), PSGMII in-band fix, ath11k NVMEM caldata support.
* **Sandiep's public `JIDU6J11-PR` branch** (github.com/Sandiep/openwrt, = upstream PR openwrt/openwrt#24432), its 4 device commits rebased onto that main — `patches/0001..0004`. Sandiep's 5th commit (PSGMII in-band) is dropped because upstream now carries the same fix.
* `patches/0005-jidu6j11-v8-adjustments.patch` (ours):
  * **WiFi stack pinned** to the PR's mac80211/backports **6.18.39** + IPQ9574 AHB patches — the exact stack v7 runs well. Upstream moved to backports 7.2 on 2026-10-08, untested with the IPQ9574 patches.
  * **Upgrade from v1–v7 accepted**: `SUPPORTED_DEVICES += jiorouter,ax6000-jidu6j11` (v7's board name), and the upgrade / U-Boot-env scripts match every `jiorouter,ax6000-jidu6j11*` name.
  * Flash layout unchanged: UBI partition **`ubi`** at 0x1700000 (size 0xe100000), kernel volume `kernel`, root `/dev/ubiblock0_1` — identical to v7.
  * **Board data** (`board-2.bin` for IPQ9574 and QCN9074, variants JIDU6J11-6111/6411/6611/6811/6911) shipped as local package `jidu6j11-board-data`, byte-identical to the files in the working v7 image (not yet in OpenWrt's qca-wireless). SHA-256: IPQ9574 `4db3f3d4…`, QCN9074 `be1ed593…`.
  * Default WiFi country **PA** (as v1–v7).
  * 512 MB memory profile via the PR's device tree (`qcom,ath11k-fw-memory-mode = <2>`) — replaces v7's "smallbuffers" variant. The board has 512 MB RAM (`free` shows ~433 MB).

## Hardening (both variants)

* LuCI **HTTPS only** (`luci-ssl`, `uhttpd.main.redirect_https=1`) — browser shows a self-signed-certificate warning once.
* Same default root password as v1–v7, set only if root has none (change it after first login).
* Time zone Asia/Kolkata. Full `wpad-mbedtls` (WPA3/SAE, 802.11k/v/r) instead of wpad-basic. zram swap, ethtool.
* Kernel modules openUF needs (`kmod-nft-bridge`, `kmod-sched-act-police`, `kmod-tun`) are built with this kernel — they cannot be installed from the online feed later because the kernel is custom.

## UniFi variant extras (`files/unifi`)

* openUF from github.com/yesrab/openUF @ 78418aef (+ our 2 patches: WPA3 `radio_caps2` for idle radios, correct **HE160** on 5 GHz) in `/usr/share/openuf-src`, installed unattended on first boot (`/usr/sbin/openuf-firstboot`), all its Lua dependencies **baked into the image**.
* **WiFi 6 on 2.4 GHz**: `/etc/config/openuf` sets `htmode_floor HE20` for band `ng` (openUF's hardware clamp still applies afterwards).
* **ubnt bootstrap account**: locked automatically after adoption — checked at **every boot** (`/etc/rc.local`) and every 5 minutes (cron `openuf-lockcheck`). `adopt-shell` registered in `/etc/shells` (otherwise adoption fails with "invalid shell").
* Converts to a wired AP before the network starts (`99-openuf-ap-prep`): no WAN, all sockets in br-lan, DHCP client, no DHCP server/firewall, open default SSIDs disabled, hostname `JioIDU-AP-xxxx` (last 4 MAC digits).
* Tailscale + its LuCI page installed from the feed on first boot (no login done; you run `tailscale up --accept-dns=false --advertise-routes=10.0.0.0/24`).
* `/opt/openuf/`, `/etc/openuf/`, `/etc/tailscale/` kept across sysupgrade.

## How to build (GitHub Actions)

1. Push this folder to a GitHub repository (e.g. `kuduku1/jidu6411-v8-unifi`).
2. **Actions → Build JIDU6J11 v8 → Run workflow**, variant `both` (or `unifi` / `stock`).
3. ~2–3 h per variant (they run in parallel). Download the artifacts `jidu6411-v8-unifi` / `jidu6411-v8-stock`: `openwrt-qualcommbe-ipq95xx-jiorouter_ax6000-jidu6j11-6411-v8-<variant>-squashfs-sysupgrade.bin`, the initramfs `.itb`, manifest, buildinfo, SHA256SUMS.

Local build: `VARIANT=unifi ./build.sh` on Ubuntu 24.04 with the packages listed in the workflow. `CHECK_ONLY=1` stops after `make defconfig`.

## Flashing (read fully first)

**Risk:** v8 is the first image from the public tree on this hardware. If it does not boot, recovery needs **UART + TFTP/initramfs**, exactly like the first OpenWrt install. Keep the v7 `.bin` and a UART adapter at hand.

1. **Canary first:** flash **v8-stock** on the 6411 that is *not* used for UniFi. Check: boots, LAN/WAN ports, LuCI over https, `iw dev` shows both radios, 5 GHz at HE160 on ch 100 works, `dmesg | grep -i ath11k` has no firmware crash.
2. Only then flash **v8-unifi** on the UniFi IDU.
3. From v7: LuCI → System → Backup/Flash → Flash image, **untick "Keep settings"** (board name and packages change; a clean first boot runs the openUF provisioning), or `sysupgrade -n /tmp/<file>.bin`.
4. UniFi: the IDU comes back as a *new* adoption (fresh openUF keys). In UniFi **Forget** the old "U6 IW" entry first, then adopt the new pending device. Re-set fixed IP (10.0.0.8 / 10.0.0.10), radio 5 GHz **160 / Auto**.
5. After adoption check: `grep '^ubnt:' /etc/shadow` starts with `ubnt:!`; `iw dev` shows **HE20** on 2.4 GHz and **HE160** on 5 GHz; `openuf deps --check` all YES; `free` ok.

## Known open items / not verified

* Not yet built or booted — everything above was checked only up to `make defconfig` (both variants, 6411 + 6111 profiles resolve; patches apply cleanly to the pinned commit).
* LAN4 (PSGMII) and the 2.4 GHz radio's HE support on IPQ9574 are not confirmed upstream. If 2.4 GHz stays HT20 even with the floor, run `iw phy phy0 info | grep -iE 'Band|HE'` — openUF only raises to HE when the radio reports HE.
* 5 GHz 160 MHz on ch 100–128 is DFS: expect a radar-check (CAC) delay after every boot/WiFi reload.
* `files/unifi` contains the openUF source as shipped in v7 (audited: only our two patches differ from upstream 78418aef).
