"""servo_twist_mode: switches MoveIt Servo to TWIST commands once it is up, then exits.

MoveIt Servo takes one command type at a time (joint jog, twist or pose), which a client
picks with the `switch_command_type` service (moveit_msgs/srv/ServoCommandType). The demo
arm takes
Conduit's twists, so this node waits for `service` (default
/servo_node/switch_command_type), asks for TWIST, retries until Servo accepts, logs
"Servo command type set to TWIST" and exits.
"""

import time

import rclpy
from moveit_msgs.srv import ServoCommandType
from rclpy.executors import ExternalShutdownException

RETRY_S = 2.0


def main():
    rclpy.init()
    node = rclpy.create_node('servo_twist_mode')
    service = node.declare_parameter('service', '/servo_node/switch_command_type').value
    client = node.create_client(ServoCommandType, service)
    logger = node.get_logger()
    try:
        while rclpy.ok():
            if not client.wait_for_service(timeout_sec=5.0):
                logger.info(f'waiting for {service}')
                continue
            future = client.call_async(
                ServoCommandType.Request(command_type=ServoCommandType.Request.TWIST))
            rclpy.spin_until_future_complete(node, future, timeout_sec=10.0)
            response = future.result()
            if response is not None and response.success:
                logger.info('Servo command type set to TWIST')
                break
            logger.warning(f'{service} did not switch to TWIST; retrying in {RETRY_S:.0f} s')
            time.sleep(RETRY_S)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == '__main__':
    main()
