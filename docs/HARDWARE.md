# Hardware notes

## Validated platforms

| Platform | Client AP profile |
|---|---|
| Raspberry Pi 3 Model B Rev 1.2 | Built-in `wlan0`, 2.4 GHz channel 6 |
| Raspberry Pi 5 Model B | Built-in `wlan0`, 5 GHz channel 36, 80 MHz, 802.11ac |

## USB upstream adapters

| Adapter | USB ID | Linux driver | Status |
|---|---|---|---|
| TP-Link Archer TX20U Nano | `35bc:0108` | `rtw89_8852bu` | Preferred and reboot-validated |
| TP-Link Archer T2U Nano | `2357:011e` | `rtw88_8821au` | Original validated adapter |
| TP-Link Archer T3U | `2357:012d` | `rtw88_8822bu` | Observed working; not the default |
| Realtek RTL8822BU generic | `0bda:b812` | `rtw88_8822bu` | USB 3 instability observed on one unit; USB 2 was stable |
| Realtek RTL8821CU generic | `0bda:c811` | `rtw88_8821cu` | Observed working; not the default |

The Archer TX20U Nano exposes a virtual driver disk briefly during boot and then
reenumerates as `35bc:0108`. A successful boot shows `rtw89_8852bu` bound to the
device and a working `wlan1` interface.

Adapters based on AICsemi AIC8800 are not currently supported. They require an
out-of-tree driver on the validated Raspberry Pi OS release.

## Using another adapter

Pass both its USB ID and expected kernel driver to the orchestrator:

```powershell
.\provision\Invoke-PiBoxClone.ps1 `
  -TargetAddress 192.168.1.123 `
  -TargetIdentityFile $HOME\.ssh\pibox_ed25519 `
  -ExpectedUsbId 2357:012d `
  -ExpectedWlan1Driver rtw88_8822bu `
  -SourceAddress 100.64.0.10 `
  -SourceIdentityFile $HOME\.ssh\pibox_ed25519
```

Treat a new adapter as experimental until it passes cold boot, association,
internet routing, repeated throughput, and kernel-log checks.
