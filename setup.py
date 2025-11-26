from setuptools import setup, find_packages

setup(
    name='prometheus-ss-exporter',

    version='2.1.1',

    description='prometheus socket statistics exporter',

    url='https://github.com/cherusk/prometheus_ss_exporter',

    author='Matthias Tafelmeier',
    author_email='matthias.tafelmeier@gmx.net',

    license='MIT',

    classifiers=[
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 2.7',
        'Programming Language :: Python :: 3',
    ],

    keywords=[
        'monitoring',
        'exporter',
        'prometheus',
        'linux',
        'socket statistics',
        'kernel statistics',
        'network stack',
        'ss2'
    ],

    packages=find_packages(),

    install_requires=[
        'pyroute2==0.7.8',
        'Twisted==24.7.0rc1',
        'prometheus-client==0.16.0',
        'PyYAML==6.0',
        'psutil==5.9.5',
        'zipp==3.15.0',
        'importlib-metadata==6.6.0',
        'typing_extensions==4.5.0'
    ],

    entry_points={
        'console_scripts': [
            'prometheus_ss_exporter=prometheus_ss_exporter.__init__:main',
        ],
    },
)
