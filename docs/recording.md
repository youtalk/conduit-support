---
title: Recording (MCAP)
description: Record Conduit's topics to an MCAP file on the device, then open it in Foxglove or replay it with ros2 bag.
---

# Recording (MCAP)

Conduit can write every topic it publishes to an **MCAP** file on the device. Open the file in
[Foxglove](https://foxglove.dev/) or [Lichtblick](https://github.com/lichtblick-suite/lichtblick),
or replay it into a ROS 2 graph with `ros2 bag play`. Recording is free.

## Record

Next to the Start button, pick what Start does:

| Mode | What happens |
| --- | --- |
| **Publish** | Sends the topics to ROS 2. Nothing is recorded |
| **Record** | Writes the topics to an MCAP file. No network or ROS 2 host is needed |
| **Both** | Sends the topics to ROS 2 and records them |

Turn on the sensors you want, then tap Start. Tap it again to stop and close the file.

A recording holds the same messages, with the same stamps, as the live topics, plus
`/tf_static`, so viewers can place point clouds and camera images in 3D. Each file carries the
message definitions it uses, so it opens without your `.msg` files.

## Find your recordings

Tap the folder button next to Settings. The list shows each recording's file name, size and date,
and the total size at the top. Swipe a recording to delete it.

Files are named `conduit_<yyyy-MM-dd>_<HH-mm-ss>.mcap`, in the device's local time.

## Share a recording

Sharing a recording off the device needs the **Recording Export** purchase (Settings → Premium
Features). With it:

- The share button on a recording opens the share sheet: AirDrop, Files, Mail and so on.
- Recordings are kept in **Documents/Recordings**, which the Files app (iPhone and iPad) and
  Finder (Mac, with the iPhone connected) can open. Recordings made before the purchase move
  there too.

Without it, recordings stay in Conduit's private storage and the share button shows a lock.

## Open a recording

**Foxglove or Lichtblick**: open the `.mcap` file. The file is indexed, so the timeline and
seeking work right away.

**ros2 bag**: Jazzy, Kilted, Lyrical and Rolling read MCAP out of the box. Humble needs the MCAP
storage plugin first.

```bash
# Humble only
sudo apt install ros-humble-rosbag2-storage-mcap

ros2 bag info conduit_2026-11-05_09-30-00.mcap
ros2 bag play conduit_2026-11-05_09-30-00.mcap
```

`audio_common_msgs/AudioData` and `point_cloud_interfaces/CompressedPointCloud2` are not in a
default ROS 2 install. To play those topics back into ROS 2, install the packages that define
them (see the [FAQ](faq.md#how-do-i-receive-microphone-data-on-ros-2) for `audio_common_msgs`), or
choose the topics to play with `ros2 bag play --topics`.

## Tips

- Camera and LiDAR fill the device quickly. Lower the camera resolution or rate in the sensor's
  settings for long recordings.
- In the background, camera and LiDAR stop (an iOS restriction), so they leave a gap in the
  recording.
- See the [FAQ](faq.md#mcap-recording) for more.
