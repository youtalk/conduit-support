# On-demand capture

Conduit 2.4.0 adds **Publish only when subscribed**. The sensors keep running, but a topic sends data only while a ROS 2 subscriber is connected to it. Use it to pull a single camera frame, point cloud, or sensor reading when you ask for it, instead of streaming every topic all the time.

## Turn it on

1. Open Settings (gear icon) in Conduit.
2. Under **Publishing**, turn on **Publish only when subscribed**.

**Good to know:**
- It is **off by default**, so existing setups keep publishing continuously.
- It is **one app-wide setting**. It applies to every sensor topic; there is no per-sensor switch. Latched topics such as `/tf_static` always publish (see below).
- It works with both the **Zenoh** and **DDS** transports.

## What you will see

- A sensor row shows **Waiting for subscriber** in place of its rate when none of that sensor's topics has a subscriber. The sensor itself is still running. Camera and LiDAR publish more than one topic, so their rows keep showing the rate while any one of their topics has a subscriber.
- When a topic has no subscriber and one appears, Conduit starts sending it and drops anything captured before that moment, so a lone subscriber's first message is a fresh capture. If another subscriber is already connected to the topic, you join the stream that is already running. For camera and depth topics on Wi-Fi, the first message typically arrives within about 0.2 to 0.3 s. Low-rate sensors such as GPS, Battery and Thermal (1 Hz) can take up to one publish period.
- When the last subscriber disconnects, the topic goes back to waiting.

## What is never held back

- **Recording.** Recording is never held back: it records the running sensors whether or not the setting is on and whether or not a subscriber is connected.
- **Latched topics such as `/tf_static`.** They always publish, and subscribers that join late still receive them.

## Capture a single message

If nothing else is subscribed to the topic, the first message is captured after you subscribe, so `ros2 topic echo --once` takes a fresh picture:

```bash
ros2 topic echo --once /conduit/camera/wide/image_raw/compressed
```

The same from Python:

```python
import rclpy
from rclpy.qos import qos_profile_sensor_data
from rclpy.wait_for_message import wait_for_message
from sensor_msgs.msg import CompressedImage

rclpy.init()
node = rclpy.create_node("conduit_capture")
ok, image = wait_for_message(
    CompressedImage,
    node,
    "/conduit/camera/wide/image_raw/compressed",
    qos_profile=qos_profile_sensor_data,
    time_to_wait=5.0,
)
if ok:
    print("captured at", image.header.stamp)
else:
    print("timed out: no message within 5 s")
node.destroy_node()
rclpy.shutdown()
```

The examples use the Camera sensor's default compressed output.

## Capture an RGB and depth pair

For a color image and a depth image of the same frame (LiDAR mode; needs an iPhone 12 Pro or newer, or an iPad Pro from 2020 or newer):

1. Enable the **Camera** sensor with the **Wide** camera, and the **LiDAR** sensor. The Wide camera and LiDAR are premium features (one-time In-App Purchases).
2. Open the LiDAR sensor's settings and set **Output** to **Depth** or **Both**. The default, **Point Cloud**, publishes no depth image.
3. Subscribe to both topics, for example `/conduit/camera/wide/image_raw/compressed` and `/conduit/camera/wide/depth/image_raw`.
4. Take one message from each and match them by equal `header.stamp`.

Each topic starts sending when its own subscriber appears, so only frames captured after **both** subscribers are connected form a pair.

## Subscriber QoS

Sensor topics publish with **best effort** reliability by default. On DDS, a subscriber that asks for reliable delivery does not match them, so it receives nothing and the sensor keeps showing **Waiting for subscriber**. Either:

- subscribe with best effort (`qos_profile_sensor_data` in rclpy, `--qos-reliability best_effort` on the `ros2` CLI), or
- set the sensor's QoS to **Reliable** in its settings.

## Limitations

- If a subscriber disconnects and reconnects within about 50 ms, Conduit may not notice the gap, so its first message can be slightly older than the new subscription (but never older than the previous one).
- Only messages that carry a header stamp are checked against the subscription time. For topics without one, such as the Microphone's audio, the first message is not guaranteed to be newer than the subscription.

## Troubleshooting

If a sensor says **Waiting for subscriber** and you expected data, see [Why does a sensor say "Waiting for subscriber"?](faq.md#why-does-a-sensor-say-waiting-for-subscriber) in the FAQ. To go back to continuous publishing, turn off **Publish only when subscribed** in Settings → Publishing.
