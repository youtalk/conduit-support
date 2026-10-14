from glob import glob

from setuptools import find_packages, setup

package_name = 'conduit_robot_harness'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/launch', glob('launch/*.launch.py')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Yutaka Kondo',
    maintainer_email='yutaka.kondo@youtalk.jp',
    description='Test robots for Conduit Robots.',
    license='Apache-2.0',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'fake_mobile_robot = conduit_robot_harness.fake_mobile_robot:main',
            'conduit_gripper_server = conduit_robot_harness.gripper_server:main',
        ],
    },
)
