FROM alpine:latest

euler-bin:
    RUN apk add gcc musl-dev
    COPY euler.c .
    RUN gcc -o euler -Wall -O3 euler.c -lm
    SAVE ARTIFACT euler
    SAVE IMAGE --push selfsigned.example.com:5000/myuser/testcache_euler_bin:mytag

calc-e:
    COPY +euler-bin/euler .
    ARG --required N
    RUN ./euler "$N" > value
    SAVE ARTIFACT value
    SAVE IMAGE --push selfsigned.example.com:5000/myuser/testcache_calc_e:mytag

test:
    ARG N=10
    COPY (+calc-e/value --N="$N") .
    RUN --no-cache echo "e calculated with N=$N is $(cat value)"
