# Roadmap

## Near term

- Add a clean-room first-device wizard that does not require a source PiBox.
- Accept AP, upstream, administrator, and exit-node configuration through a
  validated local configuration format without placing secrets on a command
  line.
- Add integration tests for routing, timer cleanup, CSRF rejection, and
  single-client Guest Login isolation.
- Test current Raspberry Pi OS updates and newer RaspAP releases in a disposable
  environment before changing the pinned versions.

## Hardware

- Collect cold-boot and throughput reports for more in-kernel USB Wi-Fi drivers.
- Validate additional Raspberry Pi 4 and Pi 5 memory variants.
- Document powered-hub and extension-cable behavior.
- Explore configurable 2.4 GHz and 5 GHz AP profiles with interference checks.

## Portability and maintenance

- Add a Linux orchestration path alongside Windows PowerShell and DPAPI.
- Evaluate an nftables-native ruleset while retaining an auditable kill switch.
- Add backup/restore and uninstall workflows.
- Produce signed release artifacts and a reproducible release checklist.

Contributors should open an issue before undertaking changes that alter the
security boundary, identity model, or normal protected traffic path.
