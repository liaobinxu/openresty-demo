#!/bin/bash

export PATH=$PATH:/data/software/openresty/bin
openresty -p `pwd`/ -c conf/nginx.conf -t
