Arduino-based sensors logger
============================

This device was developed to log data from motion sensors, temperature sensors and analog inputs to SD card.  
It also provides easy access to data and configuration through terminal software. List of supported commands:
* ls -  list root directory contents;
* cat file - print file;
* rm file - remove file;
* temp - show current temperature;
* date [unixtime] - show/set date and time;
* ver - show version of software;
* name - show device name;
* conf - show full device configuration;
* reset - reboot device.

Example of usage
================

Logger with attached motion sensor, temperature sensor, push button and potentiometer:  
![ScreenShot](https://raw.github.com/mykh/Data-Logger-Arduino/gh-pages/images/sensors_logger.jpg)

Communication with Logger via terminal:  
![ScreenShot](https://raw.github.com/mykh/Data-Logger-Arduino/gh-pages/images/terminal_window.png)
