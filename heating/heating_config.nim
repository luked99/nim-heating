
# Command line argument configuration data

type ConfigData* = tuple [
    syslog: bool,
    interval: int,          ## interval between d/b updates
]

var config*: ConfigData = (
    true,
    60*5,
)

