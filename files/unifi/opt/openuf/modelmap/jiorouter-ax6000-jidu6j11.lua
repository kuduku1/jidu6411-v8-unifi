--[[
	JioRouter AX6000 JIDU6J11 (Qualcomm IPQ95xx / QCN6411 / QCN9074) hardware profile.
	OpenWrt board name (`ubus call system board`): jiorouter,ax6000-jidu6j11
	Target: qualcommbe/ipq95xx — IPQ9574 / QCN9074 / QCN6411, NAND UBI.

	Network layout (from target/linux/qualcommbe/base-files/etc/board.d/02_network):
	  • LAN: lan1 lan2 lan3 lan4 (bridged as br-lan)
	  • WAN: wan
	  • DSA / netdev-based port reporting
	  • Uplink detection: FDB on br-lan

	Radios (Qualcomm ath11k):
	  • radio0 = 2.4 GHz (phy0, 4x4 802.11ax Wi-Fi 6 — locked to 20 MHz HE20)
	  • radio1 = 5 GHz   (phy1, 4x4 802.11ax Wi-Fi 6 — locked to 160 MHz HE160)
--]]

local dev = {}
dev.conf = {}

dev.openwrt_boards = {"jiorouter,ax6000-jidu6j11"}

dev.conf.net = {
	lan_name	= "lan",
	lan_cpueth	= "br-lan",
	lan_vlanid	= 1,
	wan_cpueth	= "wan",

	ports = {
		{idx = 1, ifname = "lan1"},
		{idx = 2, ifname = "lan2"},
		{idx = 3, ifname = "lan3"},
		{idx = 4, ifname = "lan4"},
		{idx = 5, ifname = "wan"},
	},

	uplink_detect = "fdb",
}

dev.conf.led = "green:status"

dev.conf.radio = {
	na = {
		acs_exclude_dfs = false,
		htmode_floor = "HE160",
		htmode_max = "HE160",
	},
	ng = {
		-- 2.4 GHz: Wi-Fi 6 (802.11ax) locked strictly to 20 MHz (HE20)
		htmode_floor = "HE20",
		htmode_max = "HE20",
	},
}

dev.openuf = {}
dev.openuf.uap = {
	ufmodel		= "u6iw",
	hwassign	= {"radio0", "radio1"},
}

return dev
