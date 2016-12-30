# nim-heating

## Heating controller written in Nim

Controls the heating in my house, using a pair of Raspberry Pis.

Main Pi has an i2c LCD touchscreen panel, and a Dallas 1-wire temperature sensor, and lives in the kitchen.
This runs a Postgres db to record historical data and configuration.

Second Pi lives next to the boiler and uses a relay to switch it on and off based on what the main Pi calls for.

