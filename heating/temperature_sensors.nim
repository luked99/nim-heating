import lists
import os, times, strutils
import locks
import logging
import heating

let w1_dir = "/sys/devices/w1_bus_master1"

# Base class for all sensor types
type Sensor = ref object of RootObj
method temperature(this: Sensor) : TemperatureResult {.base.} =
    quit "to override"

# A list of sensors
type SensorList = DoublyLinkedList[Sensor]

# Temperature readings taken by the worker thread get
# written in here
var latest_temperature_reading: TemperatureResult
var sequence = 0
var L: Lock           # guard access
initLock(L)

type ThreadParams = tuple[sensors: SensorList, interval: int]

# Dallas 1-wire temperature sensor
type W1Sensor = ref object of Sensor
  path: string
  fh: File

proc createW1Sensor(f: string, fh: File): W1Sensor =
    return W1Sensor(path: f, fh: fh)

# Return the temperature for a Dallas 1-wire sensor
#
# First line:  "....YES"
# Second line: "....t=21234"
method temperature(this: W1Sensor) : TemperatureResult =
    setFilePos(this.fh, 0)
    var ok = false
    var ready = false
    var t : float
    var line : system.TaintedString
    var linecount = 0
    while readLine(this.fh, line) and linecount < 2:
        inc(linecount)
        if contains(line, "YES"):
            ready = true
            continue
        let offset = find(line, "t=")
        if ready and offset > 0:
            try:
                let temp_str = line[offset+2..line.len-1]
                t = parseFloat(temp_str)/1000.0
                ok = true
                break
            except ValueError:
                ok = false
                break
    
    if not ok:
        error("could not read temperature from sensor")
    return (ok, getTime(), t)

proc w1scan(sensors: var SensorList) : int =
    ## Find Dallas 1-wire sensors
    result = 0
    for file in walkFiles w1_dir & "/*/w1_slave":
        var fh : File
        if open(fh, file):
            var line : system.TaintedString
            while readLine(fh, line):
                if contains(line, "t="):
                    var s = createW1Sensor(file, fh)
                    append(sensors, s)
                    inc(result)

proc temperature_worker2(i:int) {.thread.} =
    while true:
        sleep(1000)

proc temperature_worker(params: ThreadParams) {.thread.} =
    ## Keep reading temperature values from the sensors. The Dallas
    ## 1-wire sensors take ~1s to read, so reading needs to be in a
    ## separate thread.
    while true:
        for s in params.sensors:
            var t = s.temperature()
            L.acquire()
            latest_temperature_reading = t
            inc(sequence)
            L.release()
        sleep(params.interval)
        sleep(1000)
 
proc get_temperature*(): TemperatureResult =
    ## Return the most recent temperature reading
    L.acquire()
    result = latest_temperature_reading
    L.release()


var temperature_thread: Thread[ThreadParams]
var params: ThreadParams = (sensors: SensorList(), interval: 0)
proc temperature_sensors_init*(interval: int) =
    ## Find the temperature sensors and start polling them
    var sensors : SensorList
    let num_sensors = w1scan(sensors)
  
    if num_sensors == 0:
        error("no sensors found")
        quit(1)

    params.sensors = sensors
    params.interval = interval
    createThread(temperature_thread, temperature_worker, params)
    #var temperature_thread2: Thread[int]
    #createThread(temperature_thread2, temperature_worker2, 1)
