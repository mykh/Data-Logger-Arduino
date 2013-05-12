Arduino-based sensors logger
============================

The purpose of this device is to record data from motion sensors, temperature sensors (based on DS18B20 chip) and analog input to an SD card in CSV (comma-separated values) format so you can easily export the data to Microsoft Excel or LibreOffice Calc.
This Logger also provides easy access to data and configurations through terminal software on the go. Here is a list of supported commands:
* ls -  list root directory contents;
* cat file - print file;
* rm file - remove file;
* temp - show current temperature;
* date [unixtime] - show/set date and time;
* ver - show version of software;
* name - show device name;
* conf - show full device configuration;
* reset - reboot device.
The device consist of:
1. The "brain" is an Arduino board with ATmega328 microcontroller.
2. RTC (Real Time Clock) module based on DS1307 chip that keeps track of the current time.
3. SD card reader which supports SPI mode.
4. Optional. Bluetooth to serial module for remote access to this device.

Example of usage
================

Logger with attached motion sensor, temperature sensor, push button and potentiometer:  
![ScreenShot](https://raw.github.com/mykh/Data-Logger-Arduino/gh-pages/images/sensors_logger.jpg)

Communication with Logger via terminal:  
![ScreenShot](https://raw.github.com/mykh/Data-Logger-Arduino/gh-pages/images/terminal_window.png)
