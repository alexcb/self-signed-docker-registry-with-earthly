VERSION 0.6
FROM alpine:latest

gcc-deps:
    RUN apk add gcc musl-dev
    SAVE IMAGE --push selfsigned.example.com:5000/myuser/testcache_gcc_deps:mytag

euler-bin:
    FROM +gcc-deps
    COPY euler.c .
    RUN gcc -o euler -Wall -O3 euler.c -lm
    SAVE ARTIFACT euler
    SAVE IMAGE --push selfsigned.example.com:5000/myuser/testcache_euler_bin:mytag

pi-bin:
    FROM +gcc-deps
    COPY pi.c .
    RUN gcc -o pi -Wall -O3 pi.c -lm
    SAVE ARTIFACT pi
    SAVE IMAGE --push selfsigned.example.com:5000/myuser/testcache_pi_bin:mytag

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
