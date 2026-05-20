# Transports: Zenoh vs DDS

Conduit 2.0 supports two transports for publishing ROS 2 messages. This page helps you pick one and configure it correctly.

## Quick Decision

| Your ROS 2 setup | Recommended transport |
|------------------|-----------------------|
| Uses `rmw_zenoh_cpp` | **Zenoh** |
| Uses `rmw_cyclonedds_cpp` (default on Humble; opt-in on Jazzy/Kilted/Rolling) | **DDS** |
| Needs to cross subnets / WAN | **Zenoh** (run a router with a public IP) |
| Same-LAN, no bridge infrastructure | **DDS** |
| Corporate network blocking multicast | **Zenoh** (TCP) |

## Side-by-side

| | Zenoh | DDS (CycloneDDS) |
|---|-------|-------------------|
| ROS 2 RMW | `rmw_zenoh_cpp` | `rmw_cyclonedds_cpp` |
| Bridge required | Yes (Zenoh router, `rmw_zenohd`) | No |
| Discovery | Via router | Multicast, Unicast, or Hybrid |
| Transport | TCP (default 7447) | UDP (7400 + 250 * domain_id, and neighbors) |
| Cross-subnet | Yes | No (LAN only) |
| Works through NAT | Yes (with router on public IP) | No |
| iOS network interface | Any reachable interface | **Must bind to `en0` (WiFi)** |
| Cellular / VPN | Works (TCP egress) | Not supported |
| Domain ID range | 0-232 | 0-232 |
| Large messages | Router handles fragmentation | UDP fragmentation (WiFi may drop) |
| Setup complexity | Router needed | Direct |

## Configuration at a Glance

**Zenoh:**
- Settings → Transport: **Zenoh**
- Router Address: `<host-ip>`
- Router Port: `7447`
- Domain ID: match `ROS_DOMAIN_ID` on host

**DDS:**
- Settings → Transport: **DDS**
- Discovery Mode: **Hybrid** (recommended) / Multicast / Unicast
- Unicast Peers: add the ROS 2 host IP (required for Unicast/Hybrid)
- Network Interface: `en0` (do **not** use auto)
- Domain ID: match `ROS_DOMAIN_ID` on host

## Network Requirements

- **Zenoh:** iOS device and ROS 2 host must be able to establish a TCP connection to the Zenoh router on port 7447.
- **DDS:** iOS device and ROS 2 host must be on the same LAN subnet, with UDP traffic permitted on DDS ports (`7400 + 250 * domain_id` and adjacent). Multicast reachability is required for Multicast/Hybrid modes. Consumer APs with "AP isolation" enabled will block peer-to-peer UDP — use Unicast mode, or disable AP isolation.

## When to switch

Use Zenoh if:
- You hit fragmentation drops on DDS with large Camera/LiDAR messages.
- You need to connect from outside the LAN.
- Your WiFi AP blocks multicast and you cannot change it.

Use DDS if:
- Your ROS 2 nodes already use CycloneDDS and you don't want to install a Zenoh router.
- You want the shortest network path (no extra hop through a router).

See also:
- [FAQ.md](FAQ.md) — setup Q&A
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — failure modes for both transports
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md) — current limitations
