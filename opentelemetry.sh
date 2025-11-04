#!/bin/bash
edot-bootstrap -a install
# opentelemetry-bootstrap -a install
opentelemetry-instrument gunicorn --bind 0.0.0.0 --workers 4 app:app
