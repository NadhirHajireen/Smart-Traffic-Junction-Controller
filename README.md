# Smart Traffic Junction Controller

A scaled model of a four-way traffic junction (North/South/East/West) controlled
entirely by an **Arduino Uno (ATmega328P)** programmed in **AVR Assembly language**.

> ⚠️ **Firmware Constraint:** All firmware is written exclusively in AVR Assembly.
> No C, C++, or Arduino library functions are used anywhere in this project.

## Features

- **Normal Mode** — Timed four-way phase cycling with transitional yellow and
  all-red clearance intervals between every directional change.
- **Pedestrian Crossing** — Push-button request on the South approach, deferred
  until the current vehicle phase completes. All directions held red while a
  countdown display counts from 5 → 0.
- **Night Mode** — LDR + ADC detects low ambient light and flashes all yellow
  LEDs at 1 Hz. A 5-second hysteresis window prevents immediate exit.

## Tech Stack

| Layer       | Technology                          |
|-------------|-------------------------------------|
| MCU         | ATmega328P (Arduino Uno)            |
| Firmware    | AVR Assembly (avr-as / AVR-GCC)     |
| Sensing     | LDR voltage divider → ADC           |
| Output      | 12 traffic LEDs, 7-seg / LED bar    |
| Input       | Momentary push-button (pedestrian)  |

## Course

IE3064 — Embedded Systems Engineering
BSc (Hons) Computer Systems Engineering — Year 3, Semester 1