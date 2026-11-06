"""Stands in for the Conduit app in the RHEL and Fedora smoke test.

Reads the pairing link that pair.sh printed, checks that it matches the
sourced ROS 2, checks in like the app does, and then runs a node named like
Conduit's that publishes the latched /tf_static pair.sh waits for.
Runs on the Python 3.6 of RHEL 8 (ROS 2 Humble) too.

Usage: fake_conduit.py LINK SECONDS
"""
import json
import os
import socket
import sys
import time
import urllib.parse

import rclpy
from geometry_msgs.msg import TransformStamped
from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
from tf2_msgs.msg import TFMessage

NODE = "conduit_node"
NAMESPACE = "conduit"


def link_fields(link):
    prefix = "https://conduit.direct/pair#"
    if not link.startswith(prefix):
        sys.exit("not a pairing link: " + link)
    return dict(urllib.parse.parse_qsl(link[len(prefix):]))


def check_fields(fields):
    rmw = os.environ.get("RMW_IMPLEMENTATION", "")
    expected = {
        "v": "1",
        "transport": "zenoh" if rmw == "rmw_zenoh_cpp" else "dds",
        "distro": os.environ["ROS_DISTRO"],
        "domain": os.environ.get("ROS_DOMAIN_ID", "0"),
    }
    for key, value in expected.items():
        if fields.get(key) != value:
            sys.exit("link has %s=%r, expected %r: %r" % (key, fields.get(key), value, fields))
    for key in ("host", "checkin", "token", "name"):
        if not fields.get(key):
            sys.exit("link has no %s: %r" % (key, fields))


def check_in(fields):
    host, port = fields["checkin"].rsplit(":", 1)
    request = {
        "app_version": "smoke",
        "device": "Smoke Test",
        "namespace": NAMESPACE,
        "node": NODE,
        "token": fields["token"],
    }
    with socket.create_connection((host, int(port)), timeout=10) as conn:
        conn.sendall(json.dumps(request).encode() + b"\n")
        reply = conn.makefile().readline()
    if json.loads(reply).get("ok") is not True:
        sys.exit("check-in rejected: " + reply)
    print("fake_conduit: checked in at %s:%s" % (host, port), flush=True)


def publish_tf_static(seconds):
    rclpy.init()
    node = rclpy.create_node(NODE, namespace=NAMESPACE)
    qos = QoSProfile(depth=1, durability=DurabilityPolicy.TRANSIENT_LOCAL,
                     reliability=ReliabilityPolicy.RELIABLE)
    publisher = node.create_publisher(TFMessage, "/tf_static", qos)
    transform = TransformStamped()
    transform.header.stamp = node.get_clock().now().to_msg()
    transform.header.frame_id = "conduit_base_link"
    transform.child_frame_id = "imu_link"
    transform.transform.rotation.w = 1.0
    publisher.publish(TFMessage(transforms=[transform]))
    print("fake_conduit: /%s/%s publishes /tf_static" % (NAMESPACE, NODE), flush=True)
    deadline = time.monotonic() + seconds
    while rclpy.ok() and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.5)
    node.destroy_node()
    rclpy.shutdown()


def main():
    fields = link_fields(sys.argv[1])
    check_fields(fields)
    check_in(fields)
    publish_tf_static(float(sys.argv[2]))


if __name__ == "__main__":
    main()
