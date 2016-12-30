import db_postgres
import heating
import strutils, times, os
import logging

type HeatingDb* = ref object
    db: DbConn
    get_current: SqlPrepared
    update_current: SqlPrepared
    insert_temperature: SqlPrepared
    get_temperatures: SqlPrepared
    get_min: SqlPrepared
    get_max: SqlPrepared
    update_status: SqlPrepared
    is_heating_scheduled: SqlPrepared
    is_boosted: SqlPrepared
    is_auto_boosted: SqlPrepared

proc current_temperature*(this: HeatingDb not nil): TemperatureResult =
    let row = getRow(this.db, this.get_current, [])
    result.time = Time(parseFloat(row[0]))
    result.temperature = parseFloat(row[1])
    result.ok = true

proc heatingdb_open*(host:string = "localhost") : HeatingDb not nil =
    result = HeatingDb(db:nil)
    assert(result != nil)

    var open_tries = 0
    var db: DbConn = nil
    while db == nil:
        try:
            db = open("", "heating", "verysecret", "host=$1 dbname=heating" % host)
        except DbError:
            inc(open_tries)
            if open_tries < 10:
                info "[$1] could not open database: $2" % [$open_tries, getCurrentExceptionMsg()]
            else:
                error "could not open database, giving up: $1" % [getCurrentExceptionMsg()]
            sleep(5000)

    assert(not db.isNil)

    result.db = db
    #
    # prepare our queries
    #
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

    result.get_current = prepare(result.db, "get_current",
        sql"""select extract('epoch' from ts), temperature from current_temperature where id = 1""",
        0)

    result.get_temperatures = prepare(result.db, "get_temperatures",
        sql"""select extract(epoch from ts), temperature from temperatures
                  where extract(epoch from ts) > extract(epoch from now())-$1""",
        1)

    result.get_min = prepare(result.db, "get_min",
        sql"""select min(temperature) from temperatures
                  where extract(epoch from ts) > extract(epoch from now())-$1""",
        1)

    result.get_max = prepare(result.db, "get_max",
        sql"""select max(temperature) from temperatures
                  where extract(epoch from ts) > extract(epoch from now())-$1""",
        1)

    result.update_status = prepare(result.db, "update_status",
        sql"""insert into controller_status (heating_on) values($1)""",
        1)

    result.is_heating_scheduled = prepare(result.db, "is_heating_scheduled",
        sql"""select count(*) from schedule where
            $1 >= start_seconds and $1 <= end_seconds and weekday = $2""",
        2)

    result.is_boosted = prepare(result.db, "is_heating_boosted",
        sql"""select count(*) from boosts where ts >= (now() - interval'1 hour')""",
        0)

    result.is_auto_boosted = prepare(result.db, "is_auto_boosted",
        sql"""select count(*) from boosts where extract(dow from ts) = extract(dow from current_timestamp)
              and extract(hour from ts) = extract(hour from current_timestamp)""",
        0)

    assert(not result.isNil)
    assert(result != nil)

proc close(tdb: HeatingDb) =
    tdb.close()

proc db_update_current*(tdb: HeatingDb, t : float) =
    ## Update the database with the latest temperature
    exec(tdb.db, tdb.update_current, $t)

proc db_update_historical*(tdb: HeatingDb, t : float) =
    exec(tdb.db, tdb.insert_temperature, $t)
 
proc temperatures*(tdb: HeatingDb, max_age: int) : seq[TemperatureResult] =
    ## Return all the temperatures less than the given age (in seconds)
    let rows = getAllRows(tdb.db, tdb.get_temperatures, $max_age)
    var ret = newSeq[TemperatureResult](rows.len)
    for row in rows:
        let ok = true
        let time = Time(int(parseFloat(row[0])))
        let temp = parseFloat(row[1])
        let r : TemperatureResult = (ok, time, temp)
        ret.add(r)

    return ret

proc min*(tdb: HeatingDb, max_age: int) : float =
    ## Return the lowest temperature seen since max_age seconds ago
    let r = getRow(tdb.db, tdb.get_min, $max_age)
    return parseFloat(r[0])

proc max*(tdb: HeatingDb, max_age: int) : float =
    ## Return the highest temperature seen since max_age seconds ago
    let r = getRow(tdb.db, tdb.get_max, $max_age)
    return parseFloat(r[0])

proc thresholds*(tdb: HeatingDb) : auto =
    ## Get the temperature thresholds (low/high)
    var low, high: float
    let r = getRow(tdb.db, sql"""select low_threshold, high_threshold from config""")
    try:
        low = parseFloat(r[0])
        high = parseFloat(r[1])
    except:
        low = 19.0
        high = 22.0

    (low, high)


type ControllerStatus* = tuple [heating: bool, ts: Time]

proc controller_status*(tdb: HeatingDb) : ControllerStatus =
    ## Report the status of the boiler controller
    let row = getRow(tdb.db, sql"""select heating_on, extract(epoch from ts) from controller_status order by id desc limit 1""")
    if row[0] == "t":
        result.heating = true
    else:
        result.heating = false
    result.ts = Time(int(parseFloat(row[1])))

proc update_heating_status*(tdb: HeatingDb, status: bool) =
    ## Update what the boiler controller is doing
    tdb.db.exec(tdb.update_status, $status)

proc update_heating_status*(tdb: HeatingDb, status: RelayState) =
    var b = false
    if status == On:
        b = true

    update_heating_status(tdb, b)

proc is_heating_scheduled*(tdb: HeatingDb, localtime: TimeInfo) : bool =
    var is_weekday: bool
    case localtime.weekday
    of dSat, dSun:
        is_weekday = false
    else:
        is_weekday = true

    let seconds = localtime.hour*3600 + localtime.minute*60 + localtime.second
    let row = getRow(tdb.db, tdb.is_heating_scheduled, $seconds, $is_weekday)
    result = parseInt(row[0]) > 0

proc is_boosted*(tdb: HeatingDb) : bool =
    let row = getRow(tdb.db, tdb.is_boosted)
    result = parseInt(row[0]) > 0

proc boost_heating*(tdb: HeatingDb) : void =
    exec(tdb.db, sql"""insert into boosts (id, ts) values (DEFAULT, DEFAULT)""")

proc is_auto_boosted*(tdb: HeatingDb) : bool =
    let row = getRow(tdb.db, tdb.is_auto_boosted)
    result = parseInt(row[0]) > 0

