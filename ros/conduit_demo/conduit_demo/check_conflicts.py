"""check_conflicts: does the ROS 2 graph already use a name of the Conduit Robots demo?

Run before the demo joins a PC's graph (docker/demo/entrypoint.sh join), with that PC's
RMW_IMPLEMENTATION, ROS_DOMAIN_ID and Zenoh or CycloneDDS configuration. It joins the
graph as a plain rclpy node (no ROS 2 daemon), listens to /tf and /tf_static for the
frames in use while it waits --settle seconds for discovery and then --tf-seconds more,
reads the topic, service and action names (actions from their hidden /_action/ topics and
services), and compares them with the demo's (conduit_demo.names):

- a name the demo uses too: one `CONFLICT <name>` line each on stdout, exit 3;
- none: exit 0.

  check_conflicts [--settle 3] [--tf-seconds 2]
  check_conflicts --list   # print the graph's names instead: how names.py is refreshed
"""

import argparse
import sys
import time

from conduit_demo.names import SHARED, find_conflicts, is_node_service, split_graph

EXIT_CONFLICT = 3


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog='check_conflicts',
        description="Exit 3 when the ROS 2 graph already uses a name of the Conduit Robots "
                    "demo, printing one 'CONFLICT <name>' line each; exit 0 otherwise.")
    parser.add_argument('--settle', type=float, default=3.0,
                        help='seconds to wait for discovery (default 3)')
    parser.add_argument('--tf-seconds', type=float, default=2.0,
                        help='seconds more to sample /tf and /tf_static, which are sampled '
                             'during the discovery wait too (default 2)')
    parser.add_argument('--list', action='store_true',
                        help="print the graph's topics, services, actions and frames "
                             "(without the shared names and the services every node has) "
                             "instead of checking")
    return parser.parse_args(argv)


def read_graph(node, wait_s):
    """(topics, services, actions, frames) of the graph after `wait_s` seconds, the frames
    being those seen on /tf and /tf_static meanwhile."""
    import rclpy
    from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
    from tf2_msgs.msg import TFMessage

    frames = set()

    def on_tf(msg):
        for transform in msg.transforms:
            frames.add(transform.header.frame_id)
            frames.add(transform.child_frame_id)

    # Best effort takes /tf from reliable and best-effort publishers alike; /tf_static's
    # publishers keep their transforms for late joiners (transient local).
    node.create_subscription(
        TFMessage, '/tf', on_tf,
        QoSProfile(depth=100, reliability=ReliabilityPolicy.BEST_EFFORT))
    node.create_subscription(
        TFMessage, '/tf_static', on_tf,
        QoSProfile(depth=100, reliability=ReliabilityPolicy.RELIABLE,
                   durability=DurabilityPolicy.TRANSIENT_LOCAL))
    deadline = time.monotonic() + wait_s
    while time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=min(0.1, max(0.0, deadline - time.monotonic())))
    topics, services, actions = split_graph(
        [name for name, _ in node.get_topic_names_and_types()],
        [name for name, _ in node.get_service_names_and_types()])
    frames.discard('')
    return topics, services, actions, sorted(frames)


def print_graph(topics, services, actions, frames):
    for name in topics:
        if name not in SHARED:
            print(f'topic {name}')
    for name in services:
        if not is_node_service(name):
            print(f'service {name}')
    for name in actions:
        print(f'action {name}')
    for name in frames:
        print(f'frame {name}')


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    import rclpy
    from rclpy.executors import ExternalShutdownException

    try:
        rclpy.init()
        node = rclpy.create_node('conduit_demo_check_conflicts')
    except Exception as error:  # an unreachable Zenoh router, a bad RMW, ...
        print(f'check_conflicts: cannot join the ROS 2 graph: {error}', file=sys.stderr)
        rclpy.try_shutdown()
        return 1
    try:
        topics, services, actions, frames = read_graph(node, args.settle + args.tf_seconds)
    except (KeyboardInterrupt, ExternalShutdownException):
        return 130
    finally:
        node.destroy_node()
        rclpy.try_shutdown()

    if args.list:
        print_graph(topics, services, actions, frames)
        return 0
    conflicts = find_conflicts(topics, services, actions, frames)
    for name in conflicts:
        print(f'CONFLICT {name}', flush=True)
    if conflicts:
        print(f'check_conflicts: this graph already uses {len(conflicts)} name(s) of the '
              'Conduit Robots demo', file=sys.stderr)
        return EXIT_CONFLICT
    print(f'check_conflicts: no conflicts ({len(topics)} topics, {len(services)} services, '
          f'{len(actions)} actions, {len(frames)} frames)', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
