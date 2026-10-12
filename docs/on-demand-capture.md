# On-demand capture

Conduit 2.4.0 adds **Publish only when subscribed**. The sensors keep running, but a topic sends data only while a ROS 2 subscriber is connected to it. Use it to pull a single fresh camera frame, point cloud, or sensor reading when you ask for it, instead of streaming every topic all the time.

## Turn it on

1. Open Settings (gear icon) in Conduit.
2. Under **Publishing**, turn on **Publish only when subscribed**.

**Good to know:**
- It is **off by default**, so existing setups keep publishing continuously.
- It is **one app-wide setting**. It applies to every sensor; there is no per-sensor switch.
- It works with both the **Zenoh** and **DDS** transports.

## What you will see

- A sensor with no subscriber shows **Waiting for subscriber** in place of its rate. The sensor itself is still running.
- When a subscriber connects, Conduit starts sending that topic. Nothing captured before that moment is sent, so the subscriber's first message is always a fresh capture. On Wi-Fi it typically arrives within about 0.2-0.3 s.
- When the last subscriber disconnects, the topic goes back to waiting.

## What is never held back

- **Recording.** A recording captures everything, whether or not the setting is on and whether or not a subscriber is connected.
- **Latched topics such as `/tf_static`.** They always publish, and subscribers that join late still receive them.

## Capture a single message

Because the first message is captured after you subscribe, `ros2 topic echo --once` takes a fresh picture:

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
```

`wait_for_message` is available in recent rclpy releases. On older ones, create a subscription and use its first callback instead.

## Capture an RGB and depth pair

For a color image and a depth image of the same frame (LiDAR mode, iPhone 12 Pro or newer):

1. Enable both the **Camera** and **LiDAR** sensors.
2. In the LiDAR sensor's settings (gear icon), set **Output** to **Depth** or **Both**. The default, **Point Cloud**, publishes no depth image.
3. Subscribe to both topics, for example `/conduit/camera/wide/image_raw/compressed` and `/conduit/camera/wide/depth/image_raw`.
4. Take one message from each and match them by equal `header.stamp`.

Each topic starts sending when its own subscriber appears, so only frames captured after **both** subscribers are connected form a pair.

## Subscriber QoS

Sensor topics publish with **best effort** reliability by default. On DDS, a subscriber that asks for reliable delivery does not match them, so it receives nothing and the sensor keeps showing **Waiting for subscriber**. Either:

- subscribe with best effort (`qos_profile_sensor_data` in rclpy, `--qos-reliability best_effort` on the `ros2` CLI), or
- set the sensor's QoS to **Reliable** in its settings.

## Limitations

- Conduit looks for new subscribers every 50 ms. If a subscriber disconnects and reconnects faster than that, Conduit may not see it as new. Its first message can then have been captured before it resubscribed, though never before its previous subscription.

## Troubleshooting

If a sensor says **Waiting for subscriber** and you expected data, see [Why does a sensor say "Waiting for subscriber"?](faq.md#why-does-a-sensor-say-waiting-for-subscriber) in the FAQ. To go back to continuous publishing, turn off **Publish only when subscribed** in Settings → Publishing.
