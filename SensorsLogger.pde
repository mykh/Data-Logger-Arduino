/*
  Sensors Logger GPL Source Code
  Copyright (C) 2010-2012 mykh

  This file is part of the Sensors Logger GPL Source Code ("Sensors Logger Source Code").

  Sensors Logger Code is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Alarm Source Code is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Alarm Source Code. If not, see <http://www.gnu.org/licenses/>.
*/

#include <OneWire.h>
#include <DallasTemperature.h>
#include <Wire.h>
#include <Button.h>
#include <RTClib.h>
#include <SdFat.h>
#include <SdFatUtil.h>

//#define DEBUG

void SerialPrintErrorMessagePrefix()
{
  SerialPrint_P(PSTR("#ERR: "));
}

void DebugLog(const char* str, bool newline = true)
{
  Serial.print(str);
  if (newline)
    Serial.println();
}

void DebugLog(const int val, bool newline = true)
{
  Serial.print(val);
  if (newline)
    Serial.println();
}

#if defined(ARDUINO) && (ARDUINO < 100)
void* operator new(size_t size)
{
  return malloc(size);
};

void operator delete(void* ptr)
{
  free(ptr);
};
#endif

const int PIN_NONE = -1;
const int ANALOG_PIN_COUNT = 4;
const int MOTION_PIN_COUNT = 8;
const static byte SettingsMagic = 0x11;

struct LoggerSettings
{
  byte magic;
  char name[9];
  unsigned int version;
  int serialSpeed;
  unsigned int analogIntervalSec;
  unsigned int tempIntervalSec;
  unsigned int watchDogIntervalSec;
  int analogPins[ANALOG_PIN_COUNT];
  int motionPins[MOTION_PIN_COUNT];
  int oneWirePin;
  int sdCardErrorPin;
}
settings =
{
  SettingsMagic, // magic
  "logger",// name
  0,       // version
  9600,    // serialSpeed
  10 * 60, // analogIntervalSec
  10 * 60, // tempIntervalSec
  10 * 60, // watchDogIntervalSec
  {A0, PIN_NONE, PIN_NONE, PIN_NONE}, // analogPins
  {3, PIN_NONE, PIN_NONE, PIN_NONE, PIN_NONE, PIN_NONE, PIN_NONE, PIN_NONE}, // motionPins
  2, // oneWirePin
  8 // sdCardErrorPin
};

// Setup a oneWire instance to communicate with any OneWire devices (not just Maxim/Dallas temperature ICs)
OneWire* oneWire;
// Pass our oneWire reference to Dallas Temperature.
DallasTemperature* tempSensors;

// motion sensor
Button* motionSensors[MOTION_PIN_COUNT];
unsigned int motionValuesPrev = 0x0; // sizeof(MotionValuesPrev) >= MOTION_PIN_COUNT

bool isMotionValueChanged(int pinIndex, bool value)
{
  bool oldvalue = ((1 << pinIndex) & motionValuesPrev) >> pinIndex;
  return (oldvalue != value);
}
void motionValuePrevSet(int pinIndex, bool value)
{
  unsigned int mask = 1 << pinIndex;
  if (value)
    motionValuesPrev |= mask;
  else
    motionValuesPrev &= ~mask;
}

// RTC
RTC_DS1307 rtc;

// SD Card
Sd2Card card;
SdVolume volume;
SdFile root, file;

// store error strings in flash to save RAM
#define SDCardErrorShow(s) SDCardErrorShow_P(PSTR(s))

void SDCardErrorShow_P(const char* str, bool newline = true)
{
  SerialPrintErrorMessagePrefix();
  SerialPrint_P(str);
  if (card.errorCode())
  {
    Serial.print(' ');
    Serial.print(card.errorCode(), HEX);
    Serial.print(' ');
    Serial.print(card.errorData(), HEX);
  }
  if (newline)
    SerialPrintln_P(PSTR(""));
  if (settings.sdCardErrorPin != PIN_NONE)
  {
    digitalWrite(settings.sdCardErrorPin, HIGH);
    delay(300);
    digitalWrite(settings.sdCardErrorPin, LOW);
    delay(100);
  }
}

/*
 * User provided date time callback function.
 * See SdFile::dateTimeCallback() for usage.
 */
void SdFatDateTimeCallback(uint16_t* date, uint16_t* time) {
  // User gets date and time from GPS or real-time
  // clock in real callback function

  DateTime now = rtc.now();  
  // return date using FAT_DATE macro to format fields
  *date = FAT_DATE(now.year(), now.month(), now.day());

  // return time using FAT_TIME macro to format fields
  *time = FAT_TIME(now.hour(), now.minute(), now.second());
}

void setupSDCard()
{
  if (settings.sdCardErrorPin != PIN_NONE)
    pinMode(settings.sdCardErrorPin, OUTPUT);
  // Logger init
  // initialize the SD card at SPI_HALF_SPEED to avoid bus errors with
  // breadboards.  use SPI_FULL_SPEED for better performance.
  if (!card.init(SPI_HALF_SPEED))
    SDCardErrorShow("card.init failed");
  // initialize a FAT volume
  if (!volume.init(&card))
    SDCardErrorShow("volume.init failed");
  // open root directory
  if (!root.openRoot(&volume))
    SDCardErrorShow("openRoot failed");
  SdFile::dateTimeCallback(SdFatDateTimeCallback);
}

void setupMotionPins()
{
  for (int i = 0; i < MOTION_PIN_COUNT; i++)
    if (settings.motionPins[i] == PIN_NONE)
      motionSensors[i] = NULL;
    else
      motionSensors[i] = new Button(settings.motionPins[i], PULLDOWN);
}

void setup(void)
{
  Serial.begin(settings.serialSpeed);
  Wire.begin();
  rtc.begin();
  
  setupSDCard();
  setupMotionPins();

  if (!rtc.isrunning())
  {
    #ifdef DEBUG
    DebugLog("RTC is NOT running!");
    #endif
    // following line sets the RTC to the date & time this sketch was compiled
    //rtc.adjust(DateTime(__DATE__, __TIME__));
    rtc.adjust(DateTime(946684800)); // Saturday 1st January 2000 12:00:00 AM
  }

  SensorLog('P', 0, "SD Card & RTC init");

  oneWire = new OneWire(settings.oneWirePin);
  tempSensors = new DallasTemperature(oneWire);
  tempSensors->begin();
#ifdef DEBUG
  DebugLog("Dallas Temperature IC");
  // locate devices on the bus
  DebugLog("Locating devices...");
  DebugLog("Found ", false);
  DebugLog(tempSensors->getDeviceCount(), false);
  DebugLog(" devices.");
  // report parasite power requirements
  DebugLog("Parasite power is: ", false);
  if (tempSensors->isParasitePowerMode())
    DebugLog("ON");
  else
    DebugLog("OFF");
  DebugLog("set temp resolution");
#endif
  // set the resolution to 11 bit (Each Dallas/Maxim device is capable of several different resolutions)
  for (int i = 0; i < tempSensors->getDeviceCount(); i++)
  {
    DeviceAddress addr;
    tempSensors->getAddress(addr, i);
    tempSensors->setResolution(addr, 11); //9-12bit
  }

  SensorLog('P', 0, "Starting main loop");
}

void SensorLog(char type, int index, const char *value)
{
  DateTime now = rtc.now();
  SensorLog(type, index, value, &now);
}

void SensorLog(char type, int index, const char *value, DateTime* now)
{
  char buff[22];
  sprintf(buff, "%02d%02d%02d%c%d.CSV", now->year() - 2000, now->month(), now->day(), type, index);
  if (!file.open(&root, buff, O_CREAT | O_APPEND | O_WRITE))
    SDCardErrorShow("open failed");
  //sprintf(buff, "%02d/%02d/%04d %02d:%02d:%02d", now->month(), now->day(), now->year(), now->hour(), now->minute(), now->second());
  sprintf(buff, "%02d:%02d:%02d", now->hour(), now->minute(), now->second());
  file.print(buff);
  if (value != NULL)
  {
    file.print(',');
    file.print(value);
  }
  file.println();

  if (file.writeError)
    SDCardErrorShow("write failed");
  if (!file.close())
    SDCardErrorShow("close failed");
}

// time in milliseconds
long wdLogTime = 0L;
long analogLogTime = 0L;
long tempLogTime = 0L;

bool isDelayPassed(long *lasttime, const long delsec)
{
  long now = millis();
  long del = delsec * 1000L;
  if ((*lasttime == 0L) || ((now - *lasttime) >= del))
  {
    *lasttime = now;
    return true;
  }
  return false;
}

const char CR = 0x0D;
const char LF = 0x0A;

bool SerialReadString(char *str, int len, char delemiter = '\0') // buffer should be len+1
{
  int index = 0;
  str[index] = '\0';
  while(Serial.available() && (index < len))
  {
    char ch = Serial.read();
    delay(10);
    if ((ch == delemiter))
    {
      if (index == 0)
        continue;
      else
        break;
    }
    str[index] = ch;
    index++;
  }
  if (index == 0)
    return false;
  str[index] = '\0';
  return true;
}

void trimright(char *str)
{
  for (int i = strlen(str) - 1; i >= 0; i--)
  {
    char ch = str[i];
    if ((ch == ' ') || (ch == CR) || (ch == LF))
      str[i] = '\0';
    else
      break;
  }
}

void(* BoardReset) (void) = 0; // declare reset function @ address 0

const int CommandCount = 11;
typedef enum {cmdUnknown, cmdHelp, cmdVersion, cmdLs, cmdFileGet, cmdFileDelete, cmdTemperatureGet, cmdDateTime, cmdName, cmdConfig, cmdBoardReset} COMMAND;
COMMAND Command;
const char *CommandNames[CommandCount] = {"", "help", "ver", "ls", "cat", "rm", "temp", "date", "name", "conf", "reset"};
const int CommandMaxLength = 20;
char commandBuffer[CommandMaxLength + 1];

// TODO: check if CRLF is passed to arduino
bool commandRead()
{
  if (!SerialReadString(commandBuffer, CommandMaxLength, ' '))
    return false;
  Command = cmdUnknown;
  trimright(commandBuffer);
  for (int i = 0; i < CommandCount; i++)
    if (!strcmp(CommandNames[i], commandBuffer))
    {
      Command = COMMAND(i);
      break;
    };
#ifdef DEBUG
  Serial.print("cmd: ");
  Serial.println(commandBuffer);
#endif
  SerialReadString(commandBuffer, CommandMaxLength); // read args
  trimright(commandBuffer);
  return true;
}

void loop(void)
{
  // WD
  if (isDelayPassed(&wdLogTime, settings.watchDogIntervalSec))
    SensorLog('W', 0, NULL);

  // Temperature
  if (isDelayPassed(&tempLogTime, settings.tempIntervalSec))
  {
    int devcount = tempSensors->getDeviceCount();
    if (devcount > 0)
    {
      tempSensors->requestTemperatures(); // Send the command to get temperatures
      DateTime now = rtc.now();
      for (int i = 0; i < devcount; i++)
      {
        char buff[7];
        float tempF = tempSensors->getTempCByIndex(i);
        int tempI = int(tempF);
        sprintf(buff, "%d.%02d", tempI, abs(int((tempF - tempI) * 100)));
        SensorLog('T', i, buff, &now);
      }
    }
  }
  
  // Analog
  if (isDelayPassed(&analogLogTime, settings.analogIntervalSec))
  {
    DateTime now = rtc.now();
    for (int i = 0; i < ANALOG_PIN_COUNT; i++)
    {
      int pin = settings.analogPins[i];
      if (pin == PIN_NONE)
        continue;
      char buff[7];
      int value = 0;
      const int MeasurementCount = 10;
      for (int j = 0; j < MeasurementCount; j++)
        value += analogRead(pin);
      value /= MeasurementCount;
      sprintf(buff, "%d", value);
      SensorLog('A', i, buff, &now);
    }
  }
  
  // Motion
  for (int i = 0; i < MOTION_PIN_COUNT; i++)
  {
    Button* sensor = motionSensors[i];
    if (!sensor)
      continue;
    bool value = sensor->isPressed();
    if (isMotionValueChanged(i, value))
    {
      SensorLog('M', i, value ? "1" : "0");
      motionValuePrevSet(i, value);
    }
  }

  if (!commandRead())
    return;
    
  switch(Command)
  {
    case cmdUnknown:
    {
      SerialPrintln_P(PSTR("unknown command"));
      break;
    };
    case cmdHelp:
    {
      SerialPrintln_P(PSTR("ver; ls; cat file; rm file; temp; date [unixtime]; name [newname]; conf; reset."));
      break;
    };
    case cmdVersion:
    {
      Serial.println(settings.version);
      break;
    };
    case cmdLs:
    {
      root.ls(LS_DATE | LS_SIZE);
      break;
    }
    case cmdFileGet:
    {
      // open file
      const char *name = commandBuffer;
      if (!file.open(&root, name, O_READ))
      {
        SDCardErrorShow_P(PSTR("file.open failed: "), false);
        Serial.println(name);
        break;
      }
      int16_t c;
      while ((c = file.read()) > 0)
        Serial.print((char)c);
      file.close();
      Serial.println();
      break;
    }
    case cmdFileDelete:
    {
      const char *name = commandBuffer;
      if (!file.open(&root, name, O_WRITE))
      {
        SerialPrintErrorMessagePrefix();
        SerialPrintln_P(PSTR("can't locate file"));
        break;
      }
      if (!file.remove())
      {
        SerialPrintErrorMessagePrefix();
        SerialPrintln_P(PSTR("can't remove file"));
        break;
      }
      break;
    }
    case cmdTemperatureGet:
    {
      int devcount = tempSensors->getDeviceCount();
      if (devcount == 0)
      {
        SerialPrintErrorMessagePrefix();
        SerialPrintln_P(PSTR("there is not temp sensor"));
        break;
      }
      tempSensors->requestTemperatures(); // Send the command to get temperatures
      for (int i = 0; i < devcount; i++)
        Serial.println(tempSensors->getTempCByIndex(i));
      break;
    }
    case cmdDateTime:
    {
      DateTime now;
      const char *unixtimestr = commandBuffer;
      if (strlen(unixtimestr) != 0)
      {
        uint32_t t = atol(unixtimestr);
        if (t == 0)
        {
          SerialPrintErrorMessagePrefix();
          SerialPrintln_P(PSTR("invlid value"));
        }
        else
          rtc.adjust(DateTime(t));
      }
      now = rtc.now();
      Serial.print(now.year(), DEC);
      Serial.print('/');
      Serial.print(now.month(), DEC);
      Serial.print('/');
      Serial.print(now.day(), DEC);
      Serial.print(' ');
      Serial.print(now.hour(), DEC);
      Serial.print(':');
      Serial.print(now.minute(), DEC);
      Serial.print(':');
      Serial.print(now.second(), DEC);
      SerialPrint_P(PSTR(" unix = "));
      Serial.print(now.unixtime(), DEC);
      Serial.println();
      break;
    }
    case cmdBoardReset:
    {
      BoardReset();
      break;
    }
    case cmdConfig:
    {
      SerialPrint_P(PSTR("name: "));
      Serial.println(settings.name);
      SerialPrint_P(PSTR("version: "));
      Serial.println(settings.version);
      SerialPrint_P(PSTR("serial speed: "));
      Serial.println(settings.serialSpeed);
      SerialPrint_P(PSTR("an. int.: "));
      Serial.println(settings.analogIntervalSec);
      SerialPrint_P(PSTR("t. int.: "));
      Serial.println(settings.tempIntervalSec);
      SerialPrint_P(PSTR("wd. int.: "));
      Serial.println(settings.watchDogIntervalSec);
      SerialPrint_P(PSTR("an. pins: "));
      for (int i = 0; i < ANALOG_PIN_COUNT; i++)
      {
        Serial.print(settings.analogPins[i]);
        Serial.print(" ");
      }
      Serial.println();
      SerialPrint_P(PSTR("m. pins: "));
      for (int i = 0; i < MOTION_PIN_COUNT; i++)
      {
        Serial.print(settings.motionPins[i]);
        Serial.print(" ");
      }
      Serial.println();
      SerialPrint_P(PSTR("ow. pin: "));
      Serial.println(settings.oneWirePin);
      SerialPrint_P(PSTR("cde. pin: "));
      Serial.println(settings.sdCardErrorPin);
      break;
    }
    case cmdName:
    {
      Serial.println(settings.name);
      const char *newname = commandBuffer;
      if (strlen(newname) == 0)
        Serial.println(settings.name);
      else
        SerialPrintln_P(PSTR("set name is not impemented"));
      break;
    }
  }
}
