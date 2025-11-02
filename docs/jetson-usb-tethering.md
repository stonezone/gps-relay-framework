# Jetson USB Tethering Cheat Sheet

1. Install the required packages:
   ```bash
   sudo apt update
   sudo apt install -y usbmuxd ipheth-utils libimobiledevice-utils
   ```
2. Ensure `usbmuxd` is running (`systemctl status usbmuxd`).
3. Plug the iPhone into the Jetson and accept the "Trust this Computer" prompt.
4. Enable Personal Hotspot on the iPhone with "Allow Others to Join" disabled (USB only).
5. Verify a new network interface appears:
   ```bash
   ip addr show
   ```
6. Confirm DHCP and routing via systemd-networkd:
   ```ini
   # /etc/systemd/network/30-iphone-usb.network
   [Match]
   Name=en*

   [Network]
   DHCP=yes
   ```
7. Check connectivity:
   ```bash
   ip route
   ping -c1 $(ip route get 1.1.1.1 | awk '/src/ {print $7}')
   ```

After the interface is up, start the reference server with `python jetson/jetsrv.py` and connect from the iPhone over `ws://<jetson-ip>:8080`.
