# Architecture

## Interface roles

| Interface | Role | Default addressing |
|---|---|---|
| `wlan0` | Private PiBox access point | `10.3.141.1/24` |
| `wlan1` | Upstream Wi-Fi client | DHCP from upstream |
| `tailscale0` | Protected internet path | Assigned by Tailscale |
| `eth0` | Provisioning and recovery only | DHCP while connected |

The interface names are part of the contract. Provisioning stops if `wlan0`
is not the built-in Broadcom radio or `wlan1` does not match the expected USB
adapter driver.

## Normal mode

`pibox-routing.service` installs an idempotent `PIBOX-KILLSWITCH` chain. Client
traffic arriving on `wlan0` may leave only through `tailscale0`. Established
return traffic is allowed, all other forwarded `wlan0` traffic is rejected,
and client traffic is masqueraded on the Tailscale interface.

A policy rule keeps the PiBox client subnet in the main routing table while
Tailscale owns the default route in table 52. TCP MSS clamping prevents common
MTU-related asymmetric-throughput failures over the tunnel.

## Guest Login Mode

The portal authenticates with RaspAP and uses RaspAP's CSRF protection. When a
client enables Guest Login Mode, `/usr/local/sbin/pibox-portal`:

1. validates that the requester is on the PiBox subnet;
2. obtains the upstream DNS server learned by `wlan1`;
3. creates a source-policy rule for that single client;
4. inserts direct `wlan1` forwarding, return, DNS DNAT, and NAT rules; and
5. starts a ten-minute systemd timer.

Closing the mode, timer expiry, or a failed partial setup removes the temporary
state and rules. The broad temporary access is intentional because captive
portals may use arbitrary ports, protocols, and redirect targets.

## Identity boundaries

The source appliance may supply AP, upstream Wi-Fi, and RaspAP authentication
configuration. Each target must generate or retain its own hostname, machine ID,
SSH host keys, DHCP state, Raspberry Pi Connect identity, and Tailscale identity.
