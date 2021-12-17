FROM alpine:latest
test:
    RUN touch /this-is-my-file
    SAVE IMAGE --push selfsigned.example.com:5000/myuser/myimage:mytag
