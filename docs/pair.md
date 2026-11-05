# Connect with a QR code

<a href="https://apps.apple.com/app/id6757171237">
<img src="../assets/img/app_icon.png" width="96" height="96" alt="Download Conduit on the App Store">
</a>

<div id="open-in-conduit" hidden>
<p><a class="md-button md-button--primary" href="conduit://pair">Open in Conduit</a></p>
<p>Conduit is installed but didn't open? Tap the button.</p>
</div>

<script>
  // The pairing values stay in the URL fragment, which browsers never send to the server.
  // The only use of it here is the conduit:// link, which hands it to the app on this phone.
  (function () {
    function showOpenButton() {
      var box = document.getElementById("open-in-conduit");
      if (!box) return;
      var fragment = window.location.hash;
      var isPairingLink = /^#v=\d/.test(fragment);
      box.hidden = !isPairingLink;
      if (isPairingLink) box.querySelector("a").href = "conduit://pair" + fragment;
    }
    if (window.document$) { window.document$.subscribe(showOpenButton); } else { showOpenButton(); }
  })();
</script>

**Conduit not installed?** Install Conduit 2.6.0 or later from the [App Store](https://apps.apple.com/app/id6757171237), then scan the QR code again. The script on your PC keeps waiting.

A script on your ROS 2 PC checks the setup, shows a QR code, and waits for Conduit to check in. Scan the code with the iPhone's Camera app and Conduit fills in the connection settings for you.

## Requirements

- Ubuntu (native, not inside a container) with ROS 2 Humble, Jazzy, Kilted, Lyrical or Rolling, sourced in the shell you run the script from.
- `RMW_IMPLEMENTATION` set to `rmw_zenoh_cpp` or `rmw_cyclonedds_cpp`. Fast DDS (the default when it is unset) works, but may drop or delay high-rate topics such as the camera and LiDAR.
- The iPhone and the PC on the same Wi-Fi, or on the same Tailscale tailnet.

## Run it

```bash
curl -fsSL https://conduit.direct/pair.sh | bash
```

Options go after `bash -s --`, for example `curl -fsSL https://conduit.direct/pair.sh | bash -s -- --tailscale`. Run `bash -s -- --help` to list them.

### Read it first

The script is a single file. To read it before running it:

```bash
curl -fsSL https://conduit.direct/pair.sh | less
```

It installs nothing and never uses `sudo`. It asks before it changes anything outside its own run (for example before adding the iPhone to `~/.bashrc`), and it leaves no process running when it exits.

## What it asks

- Whether to continue with Fast DDS, if that is your RMW (CycloneDDS is recommended).
- Whether to add the iPhone as a discovery peer on this PC (DDS), and whether to add the matching line to `~/.bashrc`. The default answer to both is no.

For Zenoh, the script waits for the router (`ros2 run rmw_zenoh_cpp rmw_zenohd`) if it is not running yet.

## Tailscale

To pair over the internet or across subnets, put the iPhone and the PC on one tailnet and run the script with `--tailscale`. Tailscale works with Zenoh only, so set `RMW_IMPLEMENTATION=rmw_zenoh_cpp` and start the router first.

## Troubleshooting

If nothing happens after you scan the QR code, the script prints what to check. In short:

**Conduit never checks in**

- If the firewall (`ufw`) is on, allow the check-in port (7449 by default, TCP) and Conduit's ports: TCP 7447 for Zenoh, or UDP `7400 + 250 x domain` through the next 249 ports for DDS.
- The iPhone must be on the same Wi-Fi as the PC. Guest and office Wi-Fi often isolate clients from each other; try another network or a hotspot.
- Allow Local Network access for Conduit: iPhone Settings > Privacy & Security > Local Network.
- With Tailscale, open the Tailscale app on the iPhone and connect it to the same tailnet as the PC.
- Scan the QR code again if Conduit did not open from it.

**Conduit checked in but did not appear in the ROS 2 graph**

- Did you tap Start in Conduit?
- For Zenoh, the router must keep running.
- If the iPhone's address changed, run the script again.

**Conduit is in the graph but no message arrived on `/tf_static`**

- For DDS, shells that run ROS 2 nodes need the `export` line the script prints (or a new shell after adding it to `~/.bashrc`). Restart ROS 2 nodes that were already running and run `ros2 daemon stop`.
- With Fast DDS, switch to CycloneDDS: `export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`.
- If the iPhone's address changed, run the script again.

See also [Transports](transports.md) and [Troubleshooting](troubleshooting.md).
