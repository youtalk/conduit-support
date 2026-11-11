from setuptools import find_packages, setup

package_name = 'conduit_demo'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Yutaka Kondo',
    maintainer_email='yutaka.kondo@youtalk.jp',
    description='Map camera and battery nodes for the Conduit Robots demo',
    license='Apache-2.0',
    extras_require={'test': ['pytest']},
    entry_points={
        'console_scripts': [
            'map_camera = conduit_demo.map_camera:main',
            'battery = conduit_demo.battery:main',
        ],
    },
)
