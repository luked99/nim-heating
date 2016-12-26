
import os
import lists
import system
import strutils
import db_postgres
import times

let w1_dir = "/sys/devices/w1_bus_master1"

# Result from measuring temperature - we might fail to get anything
type TemperatureResult = tuple[ok: bool, temperature: float]

# Base class for all sensor types
type Sensor = ref object of RootObj
method temperature(this: Sensor) : TemperatureResult {.base.} =
    quit "to override"

# A list of sensors
type SensorList = DoublyLinkedList[Sensor]

# Dallas 1-wire temperature sensore
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
    
    return (ok, t)

# Find Dallas 1-wire sensors
proc w1scan(sensors: var SensorList) =
    for file in walkFiles w1_dir & "/*/w1_slave":
        var fh : File
        if open(fh, file):
            var line : system.TaintedString
            while readLine(fh, line):
                if contains(line, "t="):
                    var s = createW1Sensor(file, fh)
                    append(sensors, s)

type
    TempDbAccess = tuple[
        db: DbConn,
        update_current: SqlPrepared,
        insert_temperature: SqlPrepared,
        last_insert_time: Time
    ]

proc dbopen() : TempDbAccess =
    let db = open("localhost", "heating", "verysecret", "heating")
    result.db = db
    result.last_insert_time = Time(0)

    # prepare our queries
    result.update_current = prepare(db, "current_temperature_update",
        sql"""insert into current_temperature
                (id, temperature) values (1,$1)
                on conflict (id) do update set (id, temperature) = (1,$1)
            """,
        1)

    result.insert_temperature = prepare(db, "insert_temperature",
        sql"""insert into temperatures
                (temperature) values ($1)""",
        1)

proc dbupdate(tdb: var TempDbAccess, t : float) =
    exec(tdb.db, tdb.update_current, $t)
    let now = getTime()
    if now - tdb.last_insert_time > 5*60:
        exec(tdb.db, tdb.insert_temperature, $t)
        tdb.last_insert_time = now
 
    
var sensors : SensorList
w1scan(sensors)
var tdb = dbopen()

while true:
    for s in sensors:
        var t = s.temperature()
        if t.ok:
            echo formatFloat(t.temperature, ffDecimal, 3)
            dbupdate(tdb, t.temperature)

        sleep(5000)
