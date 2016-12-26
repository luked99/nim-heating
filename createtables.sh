
#!/bin/sh

su - postgres -c psql <<EOF

\c heating

drop table if exists temperatures;
drop table if exists current_temperature;

CREATE TABLE temperatures (
	id serial primary key,
	ts timestamp without time zone default (now() at time zone 'utc'),
	temperature float
);

CREATE TABLE current_temperature (
	id SERIAL primary key,
	ts timestamp without time zone default (now() at time zone 'utc'),
	temperature float
);

GRANT ALL on TABLE temperatures, current_temperature,
		   temperatures_id_seq, current_temperature_id_seq TO heating;

EOF

