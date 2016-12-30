
import strutils
import times
import parseopt
import posix
import heating
import heating_db
import heating_config
import logging
import netserver
import temperature_sensors

const measurement_interval = 5000

proc next_relay_state(db: HeatingDb, current_relay_state: RelayState, t: float) : RelayState =
    ## Given the latest temperature, should the relay be changed?

    var (low_threshold, high_threshold) = db.thresholds()
    let localtime = getLocalTime(getTime())
    let heating_scheduled = db.is_heating_scheduled(localtime)
    let heating_boosted = db.is_boosted()
    let heating_auto_boosted = db.is_auto_boosted()

    var next_relay_state = Unknown

    if heating_boosted:
      # if they pressed the boost button, then perhaps they are cold....crank up the heat a bit
      # but only until the end of the boost period
      #
      # Really need a way for multiple boosts to mean turn up the temperature
      low_threshold = low_threshold + 1.0
      high_threshold = high_threshold + 1.0

    if heating_scheduled or heating_boosted or heating_auto_boosted:
        if t < low_threshold:
            next_relay_state = RelayState.On
        elif t > high_threshold:
            next_relay_state = RelayState.Off
        else:
            next_relay_state = current_relay_state
    else:
        next_relay_state = RelayState.Off

    return next_relay_state
 
proc relay_status_string(relay_state: RelayState): string =
    return "heating " & $relay_state

proc notify_controller(relay_state: RelayState) =
    notify_clients(relay_status_string(relay_state) & "\r\n")

proc main() =
    var sensor_temperature:TemperatureResult = (false, Time(0), 0.0)

    let db = heatingdb_open()

    var last_insert_time = Time(0)
    var current_relay_state: RelayState = Unknown

    # report the current status for humans to read
    let status_reporter = proc(): string =
        let localtime = getLocalTime(getTime())
        let temp = sensor_temperature.temperature
        let time = sensor_temperature.time
        let heating_scheduled = db.is_heating_scheduled(localtime)
        let heating_boosted = db.is_boosted()
        return """
temperature         : $1 C
heating relay state : $2
scheduled           : $3
boosted             : $4
last update         : $5""" %
            [$temp, $current_relay_state, $heating_scheduled, $heating_boosted, $time]

    # report the current desired relay status to the boiler controller
    let relay_status_reporter = proc(): string =
        return relay_status_string(current_relay_state)

    # what to do when the 'boost' command is used
    let boost_handler = proc(): string =
        boost_heating(db)
        return "Heating boosted"
        
    let handlers: Handlers = (
      status_reporter: status_reporter,
      relay_status: relay_status_reporter,
      boost_handler: boost_handler)

    server_init(handlers)

    temperature_sensors_init(measurement_interval)

    info("starting")

    while true:
        let t = get_temperature()

        if t.ok:
            db_update_current(db, t.temperature)
            sensor_temperature = t  # maybe only do this for "important" sensors?

            # update the database, occasionally
            let now = getTime()
            if now - last_insert_time > config.interval:
                db_update_historical(db, t.temperature)
                last_insert_time = now
                let tstr = formatFloat(t.temperature, ffDecimal, 1)
                info("t=" & tstr)

            # change the relay state?
            if sensor_temperature.ok:
                let next_relay_state = next_relay_state(db, current_relay_state, sensor_temperature.temperature)
                if next_relay_state != current_relay_state:
                    current_relay_state = next_relay_state
                    notify_controller(current_relay_state)

            else:
                current_relay_state = RelayState.Off
                notify_controller(current_relay_state)

        server_serve(measurement_interval)

proc GetUid(user: string) : int =
    assert(user != nil)
    let pwent = getpwnam(user)
    if pwent == nil:
        error "could not get pwent for user " & user
    return pwent.pw_uid

proc parseCmdLine(config: var ConfigData) =

    let Usage = """
        -h | --help             Give this help
        -i | --interval=time    Seconds between database updates
    """

    var p = initOptParser()
    while true:
        next(p)
        var kind = p.kind
        var key = p.key
        var val = p.val.string

        case kind
        of cmdArgument:
            stdout.write("unexpected option\n")
            quit(Usage)

        of cmdLongoption, cmdShortOption:
            case key.string
            of "help", "h":
                stdout.write(Usage)
                quit(0)

            of "interval", "i":
                config.interval = parseInt(val)
                if config.interval < 60:
                    config.interval = 60

            else:
                quit(Usage)

        of cmdEnd:
            break

parseCmdLine(config)

main()
