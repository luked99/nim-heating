#!/bin/sh

su - postgres -c psql <<EOF

drop user heating;
drop database heating;

create user heating;
create database heating with template template0 owner heating encoding 'UTF8';

EOF

