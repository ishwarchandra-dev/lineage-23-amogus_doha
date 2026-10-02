#!/usr/bin/env bash
# =============================================================================
# LineageOS 23.2 amogus_doha — Full Device Diagnostic Dump
# =============================================================================
# Run this from your PC with the device connected via ADB.
# Usage: ./debug_device.sh [output_dir]
#
# This script captures EVERYTHING needed to debug any issue on the device.
# It creates a timestamped directory with all logs, dumps, and diagnostics.
# After it finishes, the entire directory can be analyzed offline.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="${1:-./device_dump_${TIMESTAMP}}"
mkdir -p "$OUTDIR"

# Ensure adb is available and device is connected
if ! command -v adb &>/dev/null; then
  echo "ERROR: adb not found in PATH" >&2; exit 1
fi

DEVICE_STATE=$(adb get-state 2>/dev/null || echo "none")
if [ "$DEVICE_STATE" != "device" ]; then
  echo "ERROR: No device connected (state=$DEVICE_STATE). Connect via USB and authorize ADB." >&2
  exit 1
fi

# Try to get root — needed for dmesg, some sysfs reads, tombstones
adb root 2>/dev/null || true
adb wait-for-device 2>/dev/null
sleep 3
# Verify connection recovered
if ! adb shell echo ok >/dev/null 2>&1; then
  echo "Waiting for ADB to recover after root..."
  sleep 5
  adb wait-for-device 2>/dev/null
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   LineageOS amogus_doha — Full Diagnostic Dump              ║"
echo "║   Output: $OUTDIR"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Helper: run a shell command on device and save output
# Usage: dcmd <output_file> <shell_command>
dcmd() {
  local out="$OUTDIR/$1"
  mkdir -p "$(dirname "$out")"
  shift
  echo "  ▸ $out"
  adb shell "$@" >"$out" 2>&1 || true
}

# Helper: pull a file from device
# Usage: dpull <device_path> <local_subdir>
dpull() {
  local src="$1" dst="$OUTDIR/${2:-pulled}"
  mkdir -p "$dst"
  adb pull "$src" "$dst/" >/dev/null 2>&1 || echo "  (could not pull $src)" >>"$OUTDIR/_pull_errors.log"
}

# Helper: ensure ADB is still alive, reconnect if needed
check_adb() {
  if ! adb shell echo ok >/dev/null 2>&1; then
    echo "  ⚠  ADB disconnected, waiting for reconnect..."
    adb wait-for-device 2>/dev/null
    sleep 2
  fi
}

# Helper: run dumpsys for a service
# Usage: dsvc <service_name>
dsvc() {
  dcmd "dumpsys/${1}.txt" "dumpsys $1"
}

# ═══════════════════════════════════════════════════════════════════
echo "▶ [1/20] Device Identity & Build Info"
# ═══════════════════════════════════════════════════════════════════
dcmd "info/build_props.txt" "getprop"
dcmd "info/build_display.txt" "getprop ro.build.display.id"
dcmd "info/build_date.txt" "getprop ro.build.date"
dcmd "info/kernel_version.txt" "uname -a"
dcmd "info/device_codename.txt" "getprop ro.product.device"
dcmd "info/lineage_version.txt" "getprop ro.lineage.version"
dcmd "info/build_type.txt" "getprop ro.build.type"
dcmd "info/build_fingerprint.txt" "getprop ro.build.fingerprint"
dcmd "info/selinux_mode.txt" "getenforce"
dcmd "info/uptime.txt" "uptime"
dcmd "info/date.txt" "date"
dcmd "info/meminfo.txt" "cat /proc/meminfo"
dcmd "info/cpuinfo.txt" "cat /proc/cpuinfo"
dcmd "info/mounts.txt" "mount"
dcmd "info/df.txt" "df -h"
dcmd "info/lsblk.txt" "ls -la /dev/block/by-name/"
dcmd "info/cmdline.txt" "cat /proc/cmdline"
dcmd "info/version.txt" "cat /proc/version"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [2/20] Kernel Logs (dmesg)"
# ═══════════════════════════════════════════════════════════════════
dcmd "kernel/dmesg_full.txt" "dmesg"
dcmd "kernel/dmesg_errors.txt" "dmesg -l err,warn,crit,alert,emerg"
dcmd "kernel/dmesg_touch.txt" "dmesg | grep -iE 'fts|touch|input|ts_doha|spi0|hx8|himax|goodix|synaptics|atmel'"
dcmd "kernel/dmesg_thermal.txt" "dmesg | grep -iE 'thermal|therm|trip|cool|throttl|tsens'"
dcmd "kernel/dmesg_power.txt" "dmesg | grep -iE 'cpufreq|cpu_boost|governor|schedutil|performance|sched_energy|suspend|resume|wakeup|sleep'"
dcmd "kernel/dmesg_network.txt" "dmesg | grep -iE 'wlan|wifi|rmnet|rndis|tether|bpf|netbpf|offload|ipa|qmi'"
dcmd "kernel/dmesg_audio.txt" "dmesg | grep -iE 'audio|codec|sound|alsa|wcd|bolero|apr|adsp'"
dcmd "kernel/dmesg_camera.txt" "dmesg | grep -iE 'camera|msm_cam|cci|actuator|eeprom|flash|isp|sensor.*cci'"
dcmd "kernel/dmesg_display.txt" "dmesg | grep -iE 'drm|display|dsi|mdss|mdp|panel|fb0|backlight|blank'"
dcmd "kernel/dmesg_usb.txt" "dmesg | grep -iE 'usb|dwc3|gadget|configfs|otg|xhci'"
dcmd "kernel/dmesg_battery.txt" "dmesg | grep -iE 'battery|charger|smb|qpnp|fg|fuel|bms|chg'"
dcmd "kernel/dmesg_bt.txt" "dmesg | grep -iE 'bluetooth|bt_|hci|btfm|wcnss'"
dcmd "kernel/dmesg_nfc.txt" "dmesg | grep -iE 'nfc|nxp|pn5|sec-nfc|snxxx|ese|nq'"
dcmd "kernel/dmesg_gps.txt" "dmesg | grep -iE 'gps|gnss|loc_|lowi|xtra|slim'"
dcmd "kernel/dmesg_firmware.txt" "dmesg | grep -iE 'firmware|request_firmware|ueventd.*firmware|\.bin|\.mdt'"
dcmd "kernel/dmesg_selinux.txt" "dmesg | grep -iE 'avc.*denied|selinux|audit'"
dcmd "kernel/dmesg_modules.txt" "dmesg | grep -iE 'module|modprobe|insmod'"
dcmd "kernel/dmesg_init_errors.txt" "dmesg | grep -iE 'init.*fail|init.*error|init.*denied|init.*cannot'"
dcmd "kernel/dmesg_crash.txt" "dmesg | grep -iE 'panic|oops|BUG|FORTIFY|fatal|abort|segfault'"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [3/20] Logcat (all buffers)"
# ═══════════════════════════════════════════════════════════════════
dcmd "logcat/main_system_crash.txt" "logcat -d -b main,system,crash"
dcmd "logcat/events.txt" "logcat -d -b events"
dcmd "logcat/radio.txt" "logcat -d -b radio"
dcmd "logcat/kernel.txt" "logcat -d -b kernel"
# Filtered views for quick analysis
dcmd "logcat/errors_only.txt" "logcat -d *:E"
dcmd "logcat/fatal_only.txt" "logcat -d -b crash"
dcmd "logcat/grep_touch.txt" "logcat -d | grep -iE 'fts|touch|input.*mapper|InputReader|InputDispatcher|viewport|isActive'"
dcmd "logcat/grep_thermal.txt" "logcat -d | grep -iE 'thermal|temperature|throttl|cooling'"
dcmd "logcat/grep_battery.txt" "logcat -d | grep -iE 'battery|wakelock|doze|idle|suspend|PowerManager'"
dcmd "logcat/grep_wifi.txt" "logcat -d | grep -iE 'wifi|wlan|supplicant|hostapd|softap|SoftApManager|WifiService|WifiHal'"
dcmd "logcat/grep_tether.txt" "logcat -d | grep -iE 'tether|hotspot|rndis|usb_tether|UsbDeviceManager|TetheringService|offload'"
dcmd "logcat/grep_telephony.txt" "logcat -d | grep -iE 'telephony|ril|qcrild|radio|signal|SIM|ims|volte|modem|ServiceState|NetworkRegistration|CallState'"
dcmd "logcat/grep_bt.txt" "logcat -d | grep -iE 'bluetooth|bt_|BtGatt|AdapterService|btif|hci_'"
dcmd "logcat/grep_nfc.txt" "logcat -d | grep -iE 'nfc|NfcService|nxp|NativeNfc'"
dcmd "logcat/grep_camera.txt" "logcat -d | grep -iE 'camera|CameraService|CameraProvider|CameraDevice'"
dcmd "logcat/grep_audio.txt" "logcat -d | grep -iE 'audio|AudioFlinger|AudioPolicy|AudioHAL|mixer|volume'"
dcmd "logcat/grep_display.txt" "logcat -d | grep -iE 'display|surfaceflinger|hwcomposer|gralloc|drm|DisplayManager|DisplayDevice'"
dcmd "logcat/grep_gps.txt" "logcat -d | grep -iE 'gps|location|gnss|GnssHAL|GpsLocation|LocationManager'"
dcmd "logcat/grep_fingerprint.txt" "logcat -d | grep -iE 'fingerprint|fps_id|biometric|egis|fpc|goodix'"
dcmd "logcat/grep_selinux.txt" "logcat -d | grep -iE 'avc.*denied|SELinux'"
dcmd "logcat/grep_crash.txt" "logcat -d | grep -iE 'FATAL|fatal|FORTIFY|tombstone|crash|ANR|native.*crash|signal.*SIG'"
dcmd "logcat/grep_services.txt" "logcat -d | grep -iE 'ServiceManager.*died|service.*restart|service.*start|service.*crash'"
dcmd "logcat/grep_init.txt" "logcat -d | grep -iE 'init.*service|starting.*service|init.*oneshot|init.*exec|post_boot'"
dcmd "logcat/grep_usb.txt" "logcat -d | grep -iE 'UsbDeviceManager|usb.*gadget|configfs|mtp|ptp|adb.*function'"
dcmd "logcat/grep_vibrator.txt" "logcat -d | grep -iE 'vibrat|haptic|aw86'"
dcmd "logcat/grep_sensors.txt" "logcat -d | grep -iE 'sensor|SensorService|SensorHal|accelerometer|gyro|proximity|light'"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [4/20] Touch & Input Diagnostics"
# ═══════════════════════════════════════════════════════════════════
dcmd "touch/getevent_info.txt" "getevent -lp"
dcmd "touch/dumpsys_input.txt" "dumpsys input"
dcmd "touch/input_devices.txt" "cat /proc/bus/input/devices"
dcmd "touch/fts_fw_version.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_fw_version"
dcmd "touch/fts_ic_ver.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/ic_ver"
dcmd "touch/fts_gesture_mode.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_gesture_mode"
dcmd "touch/fts_irq.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_irq"
dcmd "touch/fts_touch_point.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_touch_point"
dcmd "touch/fts_driver_info.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_driver_info"
dcmd "touch/fts_panel_supplier.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/panel_supplier"
dcmd "touch/fts_boot_mode.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_boot_mode"
dcmd "touch/fts_charger_mode.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_charger_mode"
dcmd "touch/fts_glove_mode.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_glove_mode"
dcmd "touch/fts_cover_mode.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_cover_mode"
dcmd "touch/fts_dump_reg.txt" "cat /sys/devices/platform/soc/4a88000.spi/spi_master/spi0/spi0.0/fts_dump_reg"
dcmd "touch/irq_count.txt" "cat /proc/interrupts | grep -iE 'fts|touch|input'"
dcmd "touch/firmware_files.txt" "find /vendor/firmware -name '*fts*' -o -name '*ft8*' -o -name '*focal*' -o -name '*touch*' 2>/dev/null"
dcmd "touch/idc_files.txt" "find /vendor/usr/idc /system/usr/idc -name '*.idc' 2>/dev/null -exec echo '=== {} ===' \\; -exec cat {} \\;"
dcmd "touch/keylayout_files.txt" "find /vendor/usr/keylayout /system/usr/keylayout -name '*.kl' 2>/dev/null"
# Capture 3 seconds of touch events in background (user should touch screen)
echo "    ⚠  Touch the screen for the next 3 seconds..."
timeout 3 adb shell getevent -t /dev/input/event8 >"$OUTDIR/touch/live_events_3s.txt" 2>&1 || true

# ═══════════════════════════════════════════════════════════════════
echo "▶ [5/20] Display & Graphics"
# ═══════════════════════════════════════════════════════════════════
dsvc "display"
dsvc "SurfaceFlinger"
dcmd "display/dumpsys_gpu.txt" "dumpsys gpu"
dcmd "display/drm_info.txt" "cat /sys/class/drm/card0/device/status 2>/dev/null; ls -la /sys/class/drm/"
dcmd "display/backlight.txt" "cat /sys/class/backlight/*/brightness /sys/class/backlight/*/max_brightness 2>/dev/null"
dcmd "display/panel_info.txt" "cat /sys/class/graphics/fb0/msm_fb_panel_info 2>/dev/null"
dcmd "display/fb0_info.txt" "cat /sys/class/graphics/fb0/virtual_size 2>/dev/null; cat /sys/class/graphics/fb0/stride 2>/dev/null"
dcmd "display/hwcomposer.txt" "dumpsys hwcomposer 2>/dev/null || dumpsys SurfaceFlinger --hwc"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [6/20] Thermal & Temperature"
# ═══════════════════════════════════════════════════════════════════
dcmd "thermal/dumpsys_thermalservice.txt" "dumpsys thermalservice"
dcmd "thermal/zones_all.txt" "for z in /sys/class/thermal/thermal_zone*; do echo \"--- \$(basename \$z): \$(cat \$z/type 2>/dev/null) ---\"; echo \"  temp: \$(cat \$z/temp 2>/dev/null)\"; echo \"  mode: \$(cat \$z/mode 2>/dev/null)\"; echo \"  policy: \$(cat \$z/policy 2>/dev/null)\"; for t in \$z/trip_point_*_temp; do [ -f \"\$t\" ] && echo \"  \$(basename \$t): \$(cat \$t 2>/dev/null)\"; done; done"
dcmd "thermal/cooling_devices.txt" "for c in /sys/class/thermal/cooling_device*; do echo \"--- \$(basename \$c): \$(cat \$c/type 2>/dev/null) ---\"; echo \"  cur_state: \$(cat \$c/cur_state 2>/dev/null)\"; echo \"  max_state: \$(cat \$c/max_state 2>/dev/null)\"; done"
dcmd "thermal/thermal_hal_config.txt" "cat /vendor/etc/thermal-engine*.conf 2>/dev/null; cat /vendor/etc/thermal_info_config.json 2>/dev/null"
dcmd "thermal/thermal_hal_process.txt" "ps -A | grep -iE 'thermal'"
dcmd "thermal/thermal_vintf.txt" "cat /vendor/etc/vintf/manifest/*.xml 2>/dev/null | grep -A5 -B2 thermal"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [7/20] CPU, Governor & Performance"
# ═══════════════════════════════════════════════════════════════════
dcmd "cpu/governors.txt" "for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do echo \"--- \$(basename \$(dirname \$cpu)) ---\"; echo \"  governor: \$(cat \$cpu/scaling_governor 2>/dev/null)\"; echo \"  cur_freq: \$(cat \$cpu/scaling_cur_freq 2>/dev/null)\"; echo \"  min_freq: \$(cat \$cpu/scaling_min_freq 2>/dev/null)\"; echo \"  max_freq: \$(cat \$cpu/scaling_max_freq 2>/dev/null)\"; echo \"  avail_govs: \$(cat \$cpu/scaling_available_governors 2>/dev/null)\"; echo \"  avail_freqs: \$(cat \$cpu/scaling_available_frequencies 2>/dev/null)\"; done"
dcmd "cpu/online.txt" "cat /sys/devices/system/cpu/online"
dcmd "cpu/topology.txt" "for cpu in /sys/devices/system/cpu/cpu*/topology; do echo \"--- \$(basename \$(dirname \$cpu)) ---\"; echo \"  core_id: \$(cat \$cpu/core_id 2>/dev/null)\"; echo \"  cluster: \$(cat \$cpu/physical_package_id 2>/dev/null)\"; done"
dcmd "cpu/sched_energy_aware.txt" "cat /proc/sys/kernel/sched_energy_aware 2>/dev/null"
dcmd "cpu/sched_features.txt" "cat /sys/kernel/debug/sched_features 2>/dev/null"
dcmd "cpu/loadavg.txt" "cat /proc/loadavg"
dcmd "cpu/stat.txt" "cat /proc/stat"
dcmd "cpu/top_snapshot.txt" "top -b -n 1 -H | head -80"
dcmd "cpu/ps_all.txt" "ps -A -o pid,ppid,uid,user,pcpu,pmem,vsz,rss,wchan,stat,name,args"
dcmd "cpu/post_boot_script.txt" "cat /vendor/bin/init.qcom.post_boot.sh"
dcmd "cpu/post_boot_service_status.txt" "getprop init.svc.qcom-post-boot"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [8/20] Battery, Power & Wakelocks"
# ═══════════════════════════════════════════════════════════════════
dsvc "battery"
dsvc "batterystats"
dsvc "power"
dcmd "battery/battery_sysfs.txt" "for f in /sys/class/power_supply/battery/*; do echo \"\$(basename \$f): \$(cat \$f 2>/dev/null)\"; done"
dcmd "battery/usb_supply.txt" "for f in /sys/class/power_supply/usb/*; do echo \"\$(basename \$f): \$(cat \$f 2>/dev/null)\"; done"
dcmd "battery/charger.txt" "for f in /sys/class/power_supply/qcom_battery/*; do echo \"\$(basename \$f): \$(cat \$f 2>/dev/null)\"; done 2>/dev/null; for f in /sys/class/power_supply/bms/*; do echo \"\$(basename \$f): \$(cat \$f 2>/dev/null)\"; done 2>/dev/null"
dcmd "battery/wakelocks_kernel.txt" "cat /proc/wakelocks 2>/dev/null || cat /d/wakeup_sources 2>/dev/null || cat /sys/kernel/debug/wakeup_sources 2>/dev/null"
dcmd "battery/wakelock_stats.txt" "dumpsys batterystats --wakelock"
dcmd "battery/alarm_stats.txt" "dumpsys alarm"
dcmd "battery/deviceidle.txt" "dumpsys deviceidle"
dcmd "battery/suspend_stats.txt" "cat /sys/kernel/debug/suspend_stats 2>/dev/null"
dcmd "battery/power_supply_list.txt" "ls -la /sys/class/power_supply/"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [9/20] Network, WiFi, Hotspot & Tethering"
# ═══════════════════════════════════════════════════════════════════
dsvc "wifi"
dsvc "connectivity"
dsvc "tethering"
dsvc "netd"
dsvc "network_management"
dcmd "network/ifconfig.txt" "ifconfig -a 2>/dev/null || ip addr"
dcmd "network/ip_route.txt" "ip route"
dcmd "network/ip_rule.txt" "ip rule"
dcmd "network/iptables.txt" "iptables -L -n -v 2>/dev/null"
dcmd "network/ip6tables.txt" "ip6tables -L -n -v 2>/dev/null"
dcmd "network/netstat.txt" "netstat -tlnp 2>/dev/null"
dcmd "network/wpa_supplicant_status.txt" "ps -A | grep -i wpa; dumpsys wifi | grep -A20 'WifiConfigManager'"
dcmd "network/wifi_config.txt" "cat /vendor/etc/wifi/wpa_supplicant.conf 2>/dev/null; cat /vendor/etc/wifi/wpa_supplicant_overlay.conf 2>/dev/null; cat /vendor/etc/wifi/p2p_supplicant_overlay.conf 2>/dev/null"
dcmd "network/wcnss_config.txt" "cat /vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini 2>/dev/null"
dcmd "network/hostapd_config.txt" "cat /data/vendor/wifi/hostapd/hostapd.conf 2>/dev/null; cat /data/misc/wifi/hostapd.conf 2>/dev/null"
dcmd "network/softap_state.txt" "dumpsys wifi | grep -iE 'SoftAp|softap|HalDevMgr|SAP|concurrency|iface|ActiveMode|num.*Manager'"
dcmd "network/usb_gadget.txt" "cat /config/usb_gadget/g1/UDC 2>/dev/null; echo '---functions---'; ls /config/usb_gadget/g1/functions/ 2>/dev/null; echo '---configs---'; ls -la /config/usb_gadget/g1/configs/b.1/ 2>/dev/null"
dcmd "network/rndis_state.txt" "ls -la /sys/class/android_usb/android0/f_rndis/ 2>/dev/null; cat /sys/class/android_usb/android0/f_rndis/ethaddr 2>/dev/null"
dcmd "network/tether_offload.txt" "dumpsys tethering | grep -iE 'offload|bpf|Hardware'"
dcmd "network/bpf_progs.txt" "ls -la /sys/fs/bpf/ 2>/dev/null | head -40"
dcmd "network/netbpfload.txt" "dmesg | grep -i netbpfload"
dcmd "network/dns.txt" "getprop | grep dns"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [10/20] Telephony, SIM & Calls"
# ═══════════════════════════════════════════════════════════════════
dsvc "phone"
dsvc "isms"
dsvc "isub"
dsvc "telecom"
dcmd "telephony/telephony_registry.txt" "dumpsys telephony.registry"
dcmd "telephony/carrier_config.txt" "dumpsys carrier_config"
dcmd "telephony/ril_props.txt" "getprop | grep -iE 'ril|gsm|radio|telephony|sim|cdma|lte|ims|volte|vowifi|carrier|network\.type|signal'"
dcmd "telephony/sim_state.txt" "getprop gsm.sim.state; getprop gsm.sim.state2; getprop persist.radio.multisim.config"
dcmd "telephony/signal_strength.txt" "dumpsys telephony.registry | grep -iE 'signal|strength|dbm|rsrp|rsrq|rssi|snr|level'"
dcmd "telephony/service_state.txt" "dumpsys telephony.registry | grep -iE 'ServiceState|registration|roaming|operator|dataState|voiceRegState|dataRegState'"
dcmd "telephony/call_state.txt" "dumpsys telephony.registry | grep -iE 'callState|ringing|offhook|idle'"
dcmd "telephony/data_connection.txt" "dumpsys telephony.registry | grep -iE 'dataConnection|apn|dataActivity|mDataConnectionState'"
dcmd "telephony/ims_status.txt" "dumpsys telephony.registry | grep -iE 'ims|volte|vonr|vowifi|mmtel|rcs'"
dcmd "telephony/ril_daemon.txt" "ps -A | grep -iE 'ril|qcrild|rild'"
dcmd "telephony/modem_fw.txt" "getprop gsm.version.baseband"
dcmd "telephony/network_type.txt" "getprop gsm.network.type; getprop gsm.network.type2"
dcmd "telephony/data_enabled.txt" "settings get global mobile_data; settings get global data_roaming"
dcmd "telephony/preferred_network.txt" "settings get global preferred_network_mode; settings get global preferred_network_mode1"
dcmd "telephony/multisim_config.txt" "getprop persist.radio.multisim.config; getprop ro.telephony.default_network"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [11/20] Bluetooth"
# ═══════════════════════════════════════════════════════════════════
dsvc "bluetooth_manager"
dcmd "bluetooth/bt_state.txt" "settings get global bluetooth_on; getprop persist.sys.bluetooth.on"
dcmd "bluetooth/bt_props.txt" "getprop | grep -iE 'bluetooth|bt\\.'"
dcmd "bluetooth/bt_hal.txt" "ps -A | grep -iE 'bluetooth|bt_'"
dcmd "bluetooth/bt_firmware.txt" "ls -la /vendor/bt_firmware/ 2>/dev/null"
dcmd "bluetooth/fm_hal.txt" "ls -la /vendor/lib64/vendor.qti.hardware.fm@1.0.so 2>/dev/null; ls -la /vendor/lib/vendor.qti.hardware.fm@1.0.so 2>/dev/null"
dcmd "bluetooth/bt_vintf.txt" "cat /vendor/etc/vintf/manifest.xml 2>/dev/null | grep -A10 -B2 bluetooth"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [12/20] Audio"
# ═══════════════════════════════════════════════════════════════════
dsvc "audio"
dsvc "media.audio_flinger"
dsvc "media.audio_policy"
dcmd "audio/audio_props.txt" "getprop | grep -iE 'audio|sound|volume'"
dcmd "audio/audio_hal.txt" "ps -A | grep -iE 'audio'"
dcmd "audio/mixer_state.txt" "tinymix 2>/dev/null | head -200"
dcmd "audio/pcm_devices.txt" "ls /dev/snd/ 2>/dev/null"
dcmd "audio/audio_policy.txt" "cat /vendor/etc/audio_policy_configuration.xml 2>/dev/null | head -100"
dcmd "audio/codec_info.txt" "cat /proc/asound/cards 2>/dev/null"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [13/20] Camera"
# ═══════════════════════════════════════════════════════════════════
dsvc "media.camera"
dcmd "camera/camera_props.txt" "getprop | grep -iE 'camera'"
dcmd "camera/camera_hal.txt" "ps -A | grep -iE 'camera|provider'"
dcmd "camera/camera_devices.txt" "ls -la /dev/video* /dev/v4l* 2>/dev/null"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [14/20] GPS & Location"
# ═══════════════════════════════════════════════════════════════════
dsvc "location"
dcmd "gps/gps_props.txt" "getprop | grep -iE 'gps|gnss|location|loc_|lowi|xtra'"
dcmd "gps/gps_hal.txt" "ps -A | grep -iE 'gps|gnss|lowi|xtra|loc_|slim'"
dcmd "gps/gps_config.txt" "cat /vendor/etc/gps.conf 2>/dev/null; cat /vendor/etc/flp.conf 2>/dev/null; cat /vendor/etc/izat.conf 2>/dev/null"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [15/20] Sensors, Fingerprint & Vibrator"
# ═══════════════════════════════════════════════════════════════════
dsvc "sensorservice"
dcmd "sensors/sensor_list.txt" "dumpsys sensorservice | head -100"
dcmd "sensors/sensor_props.txt" "getprop | grep -iE 'sensor'"
dcmd "sensors/sensor_hal.txt" "ps -A | grep -iE 'sensor'"
dcmd "sensors/sensor_config_dir.txt" "ls -laR /vendor/etc/sensors/ 2>/dev/null"

dsvc "fingerprint"
dcmd "fingerprint/fps_hal.txt" "ps -A | grep -iE 'fingerprint|fps|biometric|egis|fpc'"
dcmd "fingerprint/fps_props.txt" "getprop | grep -iE 'fingerprint|fps|biometric'"
dcmd "fingerprint/fps_id.txt" "cat /proc/hw/fps_id/ascii 2>/dev/null"
dcmd "fingerprint/fps_script.txt" "cat /vendor/bin/init.oem.fingerprint2.sh 2>/dev/null"

dcmd "vibrator/vibrator_hal.txt" "ps -A | grep -iE 'vibrat'"
dcmd "vibrator/vibrator_sysfs.txt" "ls -la /sys/class/leds/vibrator/ 2>/dev/null; cat /sys/class/leds/vibrator/activate 2>/dev/null"
dcmd "vibrator/aw_haptic.txt" "find /sys -name '*aw86*' -o -name '*haptic*' 2>/dev/null | head -20"
dcmd "vibrator/modules_load.txt" "cat /vendor/lib/modules/modules.load 2>/dev/null"
dcmd "vibrator/loaded_modules.txt" "lsmod 2>/dev/null || cat /proc/modules"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [16/20] USB & Storage"
# ═══════════════════════════════════════════════════════════════════
dsvc "usb"
dcmd "usb/usb_state.txt" "getprop | grep -iE 'usb|mtp|ptp|adb'"
dcmd "usb/usb_gadget.txt" "cat /config/usb_gadget/g1/UDC 2>/dev/null"
dcmd "usb/usb_functions.txt" "ls -la /config/usb_gadget/g1/functions/ 2>/dev/null"
dcmd "usb/usb_speed.txt" "cat /sys/class/udc/*/device/speed 2>/dev/null"
dcmd "usb/usb_hal.txt" "ps -A | grep -iE 'usb'"
dcmd "usb/usb_devices.txt" "cat /sys/kernel/debug/usb/devices 2>/dev/null"
dsvc "mount"
dsvc "diskstats"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [17/20] SELinux & Security"
# ═══════════════════════════════════════════════════════════════════
dcmd "selinux/enforcing.txt" "getenforce"
dcmd "selinux/all_denials_dmesg.txt" "dmesg | grep 'avc.*denied'"
dcmd "selinux/all_denials_logcat.txt" "logcat -d -b all | grep -iE 'avc.*denied|selinux'"
dcmd "selinux/file_contexts_check.txt" "ls -laZ /vendor/bin/hw/android.hardware.thermal* 2>/dev/null; ls -laZ /vendor/bin/init.qcom.post_boot.sh 2>/dev/null; ls -laZ /vendor/bin/sh 2>/dev/null"
dcmd "selinux/property_denials.txt" "dmesg | grep 'avc.*denied.*property_service'"
dcmd "selinux/boot_props.txt" "getprop | grep -iE 'selinux|verity|avb|dm_verity'"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [18/20] Crashes, Tombstones & ANRs"
# ═══════════════════════════════════════════════════════════════════
dcmd "crashes/tombstone_list.txt" "ls -la /data/tombstones/ 2>/dev/null"
# Pull tombstones carefully (these can cause ADB disconnects)
for i in $(seq 0 9); do
  f="tombstone_$(printf '%02d' $i)"
  dpull "/data/tombstones/$f" "crashes/tombstones" 2>/dev/null || true
  sleep 0.5
done
check_adb
dcmd "crashes/anr_list.txt" "ls -la /data/anr/ 2>/dev/null"
dpull "/data/anr/traces.txt" "crashes/anr" 2>/dev/null || true
check_adb
dcmd "crashes/dropbox_list.txt" "ls -la /data/system/dropbox/ 2>/dev/null | tail -40"
dcmd "crashes/native_crashes.txt" "logcat -d -b crash"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [19/20] Services, Init & VINTF"
# ═══════════════════════════════════════════════════════════════════
dcmd "services/service_list.txt" "service list"
dcmd "services/init_services.txt" "getprop | grep 'init.svc\.' | sort"
dcmd "services/crashed_services.txt" "getprop | grep 'init.svc\.' | grep -iE 'stopped|restarting'"
dcmd "services/hal_processes.txt" "ps -A | grep -E 'android\.(hardware|hidl)|vendor\.' | sort"
dcmd "services/all_processes.txt" "ps -Af"
dcmd "services/vintf_manifest.txt" "cat /vendor/etc/vintf/manifest.xml 2>/dev/null"
dcmd "services/vintf_fragments.txt" "for f in /vendor/etc/vintf/manifest/*.xml; do echo '=== \$f ==='; cat \$f 2>/dev/null; done"
dcmd "services/device_manifest.txt" "cat /vendor/etc/vintf/manifest.xml 2>/dev/null"
dcmd "services/framework_manifest.txt" "cat /system/etc/vintf/manifest.xml 2>/dev/null | head -100"
dcmd "services/compatibility_matrix.txt" "cat /system/etc/vintf/compatibility_matrix.current.xml 2>/dev/null | head -100"
dcmd "services/init_rc_files.txt" "find /vendor/etc/init -name '*.rc' 2>/dev/null"
dcmd "services/init_rc_contents.txt" "for f in /vendor/etc/init/*.rc; do echo '=== \$f ==='; cat \$f 2>/dev/null; echo; done"
dcmd "services/hwservicemanager.txt" "lshal --neat 2>/dev/null | head -200"

# ═══════════════════════════════════════════════════════════════════
echo "▶ [20/20] Miscellaneous & System Health"
# ═══════════════════════════════════════════════════════════════════
dsvc "window"
dsvc "package"
dsvc "activity"
dsvc "notification"
dsvc "accessibility"
dcmd "misc/settings_system.txt" "settings list system"
dcmd "misc/settings_secure.txt" "settings list secure"
dcmd "misc/settings_global.txt" "settings list global"
dcmd "misc/installed_packages.txt" "pm list packages -f"
dcmd "misc/disabled_packages.txt" "pm list packages -d"
dcmd "misc/overlays.txt" "cmd overlay list 2>/dev/null"
dcmd "misc/runtime_permissions.txt" "dumpsys package | grep -A5 'runtime permissions' | head -100"
dcmd "misc/disk_io.txt" "cat /proc/diskstats"
dcmd "misc/vmstat.txt" "cat /proc/vmstat"
dcmd "misc/zoneinfo.txt" "cat /proc/zoneinfo | head -100"
dcmd "misc/slabinfo.txt" "cat /proc/slabinfo 2>/dev/null | head -50"
dcmd "misc/timezone.txt" "getprop persist.sys.timezone"
dcmd "misc/locale.txt" "getprop persist.sys.locale"
dcmd "misc/encryption.txt" "getprop ro.crypto.state"
dcmd "misc/treble.txt" "getprop ro.treble.enabled"

# ═══════════════════════════════════════════════════════════════════
# Generate a quick summary report
# ═══════════════════════════════════════════════════════════════════
echo ""
echo "▶ Generating summary..."

{
  echo "═══════════════════════════════════════════════════════════════"
  echo " DEVICE DIAGNOSTIC SUMMARY"
  echo " Generated: $(date)"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  echo "── Device ──"
  cat "$OUTDIR/info/lineage_version.txt" 2>/dev/null
  cat "$OUTDIR/info/kernel_version.txt" 2>/dev/null
  cat "$OUTDIR/info/build_type.txt" 2>/dev/null
  echo ""

  echo "── Critical: CPU Governor ──"
  grep -E "governor:" "$OUTDIR/cpu/governors.txt" 2>/dev/null
  echo ""

  echo "── Critical: Touch ──"
  grep -E "mode -|isActive" "$OUTDIR/touch/dumpsys_input.txt" 2>/dev/null | head -5
  cat "$OUTDIR/touch/fts_fw_version.txt" 2>/dev/null
  cat "$OUTDIR/touch/fts_panel_supplier.txt" 2>/dev/null
  echo ""

  echo "── Critical: Thermal ──"
  grep "Temperature{" "$OUTDIR/thermal/dumpsys_thermalservice.txt" 2>/dev/null | head -12
  echo ""

  echo "── Critical: post_boot status ──"
  cat "$OUTDIR/cpu/post_boot_service_status.txt" 2>/dev/null
  echo ""

  echo "── Crashed/Stopped Services ──"
  cat "$OUTDIR/services/crashed_services.txt" 2>/dev/null
  echo ""

  echo "── SELinux Denials (count) ──"
  wc -l < "$OUTDIR/selinux/all_denials_dmesg.txt" 2>/dev/null || echo "0"
  echo ""

  echo "── Tombstones ──"
  cat "$OUTDIR/crashes/tombstone_list.txt" 2>/dev/null | head -10
  echo ""

  echo "── SIM State ──"
  grep "gsm.sim.state" "$OUTDIR/info/build_props.txt" 2>/dev/null
  echo ""

  echo "── Battery ──"
  grep -E "level:|status:|temperature:|health:" "$OUTDIR/dumpsys/battery.txt" 2>/dev/null
  echo ""

  echo "── WiFi ──"
  grep "mIfaceIsUp" "$OUTDIR/dumpsys/wifi.txt" 2>/dev/null
  grep "STA.*AP.*Concurrency" "$OUTDIR/dumpsys/wifi.txt" 2>/dev/null
  echo ""

  echo "── USB Tethering ──"
  grep "mUsbTetheringFunction" "$OUTDIR/dumpsys/tethering.txt" 2>/dev/null
  grep "Offload HAL" "$OUTDIR/dumpsys/tethering.txt" 2>/dev/null
  echo ""

} > "$OUTDIR/SUMMARY.txt"

cat "$OUTDIR/SUMMARY.txt"

# Final size
TOTAL_SIZE=$(du -sh "$OUTDIR" | cut -f1)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   ✅ Diagnostic dump complete!                              ║"
echo "║   Output: $OUTDIR ($TOTAL_SIZE)"
echo "║                                                              ║"
echo "║   Key files to review first:                                 ║"
echo "║     SUMMARY.txt            — Quick health overview           ║"
echo "║     kernel/dmesg_crash.txt — Kernel crashes/FORTIFY          ║"
echo "║     kernel/dmesg_touch.txt — Touch driver logs               ║"
echo "║     kernel/dmesg_selinux.txt — SELinux denials               ║"
echo "║     logcat/fatal_only.txt  — All fatal crashes               ║"
echo "║     crashes/tombstones/    — Native crash dumps              ║"
echo "║     cpu/governors.txt      — CPU governor state              ║"
echo "║     touch/fts_*.txt        — Touch IC state                  ║"
echo "║     telephony/             — SIM & call diagnostics          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
