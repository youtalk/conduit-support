from glob import glob

from setuptools import find_packages, setup

package_name = 'conduit_demo'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/launch', glob('launch/*.launch.py')),
        ('share/' + package_name + '/scripts', glob('scripts/*.sh')),
        ('share/' + package_name + '/urdf', glob('urdf/*.xacro')),
        ('share/' + package_name + '/worlds', glob('worlds/*.sdf')),
        ('share/' + package_name + '/config', glob('config/*.yaml')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Yutaka Kondo',
    maintainer_email='yutaka.kondo@youtalk.jp',
    description='The Conduit Robots demo: a TurtleBot3 with a map camera and a Panda in Gazebo',
    license='Apache-2.0',
    extras_require={'test': ['pytest']},
    entry_points={
        'console_scripts': [
            'map_camera = conduit_demo.map_camera:main',
            'battery = conduit_demo.battery:main',
            'initial_pose = conduit_demo.initial_pose:main',
            'gripper_command = conduit_demo.gripper_command:main',
            'servo_twist_mode = conduit_demo.servo_twist_mode:main',
        ],
    },
)
