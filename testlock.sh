#!/bin/bash

wrk -t10 -c400 -d5s http://127.0.0.1:8080/
