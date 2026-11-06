# Transports: Zenoh vs DDS

Conduit publishes ROS 2 messages over one of two transports. This page helps you pick one and set it up.

The easiest way to set up either one is [Connect with a QR code](pair.md) (Conduit 2.6.0 or later): a script on your ROS 2 PC checks the setup, and scanning its QR code fills in the connection settings in Conduit.

## Quick decision

| Your ROS 2 setup | Transport |
|------------------|-----------|
| Uses `rmw_zenoh_cpp` | **Zenoh** |
| Uses `rmw_cyclonedds_cpp` | **DDS** |
| Device and host on different subnets, or over the internet | **Zenoh** (for example over Tailscale) |
| Same LAN, and you don't want to run a router | **DDS** |
| Network blocks multicast or isolates Wi-Fi clients | **Zenoh** (TCP) |

The default RMW on Humble, Jazzy, Kilted, Lyrical and Rolling is Fast DDS (`rmw_fastrtps_cpp`), so set `RMW_IMPLEMENTATION` on the host. A Fast DDS host can discover Conduit over DDS, but may drop or delay high-rate topics such as the camera and LiDAR.

## Side by side

| | Zenoh | DDS (CycloneDDS) |
|---|-------|-------------------|
| ROS 2 RMW | `rmw_zenoh_cpp` | `rmw_cyclonedds_cpp` |
| Router required | Yes (`rmw_zenohd`) | No |
| Discovery | Through the router | Multicast; add peers for unicast on top (hybrid) |
| Network traffic | TCP, port 7447 by default | UDP, from `7400 + 250 × domain ID` |
| Across subnets | Yes | No (same LAN only) |
| Tailscale | Yes | No |
| Network interface on iPhone / iPad | Any that reaches the router | **en0 (WiFi)** |
| Domain ID | 0–232 | 0–232 |
| Large messages (camera, LiDAR) | TCP to the router | UDP fragments; busy Wi-Fi may drop them |

Conduit embeds CycloneDDS 11.0.1. Use the `rmw_cyclonedds_cpp` that ships with your ROS 2 distribution.

## Settings

Open Settings (gear icon) in Conduit. Changes are saved as you make them; tap **Done** to close. You cannot change the connection while publishing.

**Zenoh:**

- **Transport**: Zenoh
- **Router Address**: the IP address of the host that runs `rmw_zenohd`
- **Router Port**: `7447`
- **Domain ID**: the host's `ROS_DOMAIN_ID`
- **Distribution**: your host's ROS 2 release (Lyrical by default)

Start the router on the host:

```bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
ros2 run rmw_zenoh_cpp rmw_zenohd
```

**DDS:**

- **Transport**: DDS
- **Discovery**: opens the **DDS Discovery** page:
    - **Peers**: add the ROS 2 host's IP address. With no peers, Conduit uses multicast discovery. With peers, it also sends unicast discovery to them (hybrid).
    - **Network Interface**: **en0 (WiFi)** on iPhone and iPad.
    - **This Device** shows the device's IP address.

- **Domain ID**: the host's `ROS_DOMAIN_ID`
- **Distribution**: your host's ROS 2 release (Lyrical by default)

Discovery changes apply the next time you tap Start.

On the host, add the device's address (**This Device**) as a peer too:

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI='<CycloneDDS><Domain><Discovery><Peers><Peer address="DEVICE_IP"/></Peers></Discovery></Domain></CycloneDDS>'
ros2 daemon stop
```

Replace `DEVICE_IP` with the address shown under **This Device**. Run `ros2 daemon stop` after you change `RMW_IMPLEMENTATION`, `ROS_DOMAIN_ID` or `CYCLONEDDS_URI`, so the `ros2` CLI picks up the change.

## Network requirements

- **Zenoh:** the device must reach the router over TCP (port 7447 by default). Allow that port in the host's firewall.
- **DDS:** the device and the host must be on the same LAN subnet, with UDP allowed on the DDS ports: `7400 + 250 × domain ID` and the next 249 ports. Guest and office Wi-Fi often isolate clients from each other ("AP isolation"), which blocks DDS. Use Zenoh on such networks, or disable AP isolation.

## Tailscale

Zenoh works over a [Tailscale](https://tailscale.com) tailnet, so the device and the host can be on different networks. Put both on the same tailnet and use the host's Tailscale address as the Router Address. The QR code script sets this up with `--tailscale`; see [Connect with a QR code](pair.md#tailscale). DDS does not work over Tailscale.

## When to switch

Use Zenoh if:

- Large camera or LiDAR messages drop on DDS.
- You need to connect from another subnet or from outside the LAN.
- Your Wi-Fi blocks multicast or isolates clients, and you cannot change it.

Use DDS if:

- Your ROS 2 nodes already use CycloneDDS and you don't want to run a Zenoh router.
- You want the shortest network path, with no hop through a router.

See also:

- [FAQ](faq.md): setup questions
- [Troubleshooting](troubleshooting.md): problems with either transport
- [Known issues](known-issues.md): current limitations
