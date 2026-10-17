"""Conduit's mobile drive view driving a Kachaka through the kachaka-api ROS 2 bridge.

Starts conduit_teleop with Kachaka's speeds (config/kachaka_teleop_twist_joy.yaml) and its
output on <kachaka_namespace>/manual_control/cmd_vel, then enables Kachaka's manual control
with <kachaka_namespace>/manual_control/set_enabled.
"""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess, IncludeLaunchDescription, TimerAction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    joy_topic = LaunchConfiguration("joy_topic")
    namespace = LaunchConfiguration("kachaka_namespace")

    teleop = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            PathJoinSubstitution([FindPackageShare("conduit_teleop"), "launch", "conduit_teleop.launch.py"])
        ),
        launch_arguments={
            "joy_topic": joy_topic,
            "cmd_vel_topic": [namespace, "/manual_control/cmd_vel"],
            # Full stick = the bridge's top speeds (0.3 m/s, 1.57 rad/s).
            "params_file": PathJoinSubstitution(
                [FindPackageShare("conduit_teleop"), "config", "kachaka_teleop_twist_joy.yaml"]
            ),
        }.items(),
    )

    # The bridge accepts velocity only while manual control is enabled.
    enable_manual_control = TimerAction(
        period=2.0,
        actions=[
            ExecuteProcess(
                cmd=["ros2", "service", "call", [namespace, "/manual_control/set_enabled"],
                     "std_srvs/srv/SetBool", "{data: true}"],
                output="screen",
            )
        ],
    )

    return LaunchDescription([
        DeclareLaunchArgument("joy_topic", default_value="/joy",
                              description="Joy topic of the Conduit robot profile"),
        DeclareLaunchArgument("kachaka_namespace", default_value="/kachaka",
                              description="Namespace of the kachaka-api ROS 2 bridge"),
        teleop,
        enable_manual_control,
    ])
