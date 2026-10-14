from setuptools import find_packages, setup

package_name = 'conduit_gate_probe'

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
    description='Host-clock timing probe for the Conduit 3.0 device gates.',
    license='Apache-2.0',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'conduit_gate_probe = conduit_gate_probe.probe:main',
            'conduit_gate_ping = conduit_gate_probe.ping_client:main',
        ],
    },
)
