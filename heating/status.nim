
import times, strutils
import heating_db

let db = heatingdb_open(host="heating")
let localtime = getLocalTime(getTime())
let heating_scheduled = db.is_heating_scheduled(localtime)
echo "heating_scheduled: $1" % $heating_scheduled

