from glob import glob

from setuptools import find_packages, setup

package_name = 'conduit_teleop'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/config', glob('config/*.yaml')),
        ('share/' + package_name + '/launch', glob('launch/*.launch.py')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Yutaka Kondo',
    maintainer_email='yutaka.kondo@youtalk.jp',
    description='teleop_twist_joy with a Joy watchdog, and a MoveIt named-pose node, for driving robots from Conduit',
    license='Apache-2.0',
    extras_require={'test': ['pytest']},
    entry_points={
        'console_scripts': [
            'joy_watchdog = conduit_teleop.joy_watchdog:main',
            'named_pose_node = conduit_teleop.named_pose_node:main',
        ],
    },
)
