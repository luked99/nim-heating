#
import times

# Result from measuring temperature - we might fail to get anything
type TemperatureResult* = tuple
  [ok: bool, time: Time, temperature: float]

type RelayState* = enum
  Unknown, On, Off
